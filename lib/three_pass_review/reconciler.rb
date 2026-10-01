# frozen_string_literal: true

module ThreePassReview
  # Deterministic, no model call: validate, cluster duplicates, merge, score,
  # threshold, rank, cap.
  class Reconciler
    # Title-token Jaccard similarity at or above which two findings on nearby
    # lines are treated as the same problem.
    TITLE_SIMILARITY = 0.5
    MAX_CONFIDENCE = 0.99
    STOPWORDS = %w[a an the is are be in on of to for and or not no with without into from by at as it this that].freeze

    Reconciled = Data.define(:file, :line_start, :line_end, :category, :subcategory, :severity, :confidence,
      :title, :explanation, :evidence, :suggested_fix, :passes, :source_confidences) do
      def location
        (line_start == line_end) ? "#{file}:#{line_start}" : "#{file}:#{line_start}-#{line_end}"
      end
    end

    Invalid = Data.define(:source, :reason, :finding)
    Result = Data.define(:findings, :dropped_invalid, :below_threshold, :cut, :invalid)

    def initialize(diff:, confidence_threshold: 0.6, max_comments: 10, merge_line_gap: 3)
      @diff = diff
      @threshold = confidence_threshold
      @max_comments = max_comments
      @gap = merge_line_gap
    end

    def reconcile(pass_results)
      valid, invalid = validate(pass_results)
      clusters = cluster(valid).map { |group| merge(group) }
      kept, below = clusters.partition { |c| c.confidence >= @threshold }
      ranked = kept.sort_by { |c| rank_key(c) }
      ThreePassReview.deep_freeze(Result.new(
        findings: ranked.first(@max_comments), dropped_invalid: invalid.size, below_threshold: below.size,
        cut: [ranked.size - @max_comments, 0].max, invalid: invalid
      ))
    end

    private

    # Each [finding, source]. A source is one call: the pass name, plus the
    # sample number when a pass ran more than once (single_sampled).
    def validate(pass_results)
      sampled = pass_results.group_by(&:pass).select { |_, rs| rs.size > 1 }.keys
      valid = []
      invalid = []
      pass_results.each do |result|
        source = sampled.include?(result.pass) ? "#{result.pass}##{result.sample}" : result.pass
        result.findings.each do |raw|
          finding, reason = Finding.validate(raw, diff: @diff, pass: result.pass)
          finding ? valid << [finding, source] : invalid << Invalid.new(source: source, reason: reason, finding: raw)
        end
      end
      [valid, invalid]
    end

    # Union-find over every pair, so clusters are transitive and the result
    # doesn't depend on the order findings arrive in.
    def cluster(items)
      parent = (0...items.size).to_a
      find = ->(i) { (parent[i] == i) ? i : (parent[i] = find.call(parent[i])) }
      items.each_index do |i|
        ((i + 1)...items.size).each do |j|
          parent[find.call(j)] = find.call(i) if duplicate?(items[i].first, items[j].first)
        end
      end
      items.each_index.group_by { |i| find.call(i) }.values.map { |idx| idx.map { |i| items[i] } }
    end

    def duplicate?(a, b)
      return false unless a.file == b.file
      return false unless a.line_start <= b.line_end + @gap && b.line_start <= a.line_end + @gap

      a.subcategory == b.subcategory || title_similarity(a.title, b.title) >= TITLE_SIMILARITY
    end

    def title_similarity(a, b)
      ta = tokens(a)
      tb = tokens(b)
      return 0.0 if ta.empty? || tb.empty?

      (ta & tb).size.to_f / (ta | tb).size
    end

    def tokens(title)
      title.downcase.scan(/[a-z0-9_]+/).reject { |t| STOPWORDS.include?(t) }.uniq
    end

    def merge(group)
      findings = group.map(&:first)
      # The finding that speaks for the cluster: most severe, then most sure.
      lead = findings.min_by { |f| [f.severity_rank, -f.confidence, f.line_start, f.title] }
      narrowest = findings.min_by { |f| [f.line_end - f.line_start, f.line_start] }
      per_source = group.each_with_object({}) do |(f, source), best|
        best[source] = [best[source] || 0.0, f.confidence].max
      end
      Reconciled.new(
        file: lead.file, line_start: narrowest.line_start, line_end: narrowest.line_end,
        category: lead.category, subcategory: lead.subcategory, severity: lead.severity,
        confidence: combine(per_source.values), title: lead.title, explanation: lead.explanation,
        evidence: findings.map { |f| f.evidence.strip }.reject(&:empty?).uniq,
        suggested_fix: lead.suggested_fix, passes: per_source.keys.sort, source_confidences: per_source.sort.to_h
      )
    end

    # 1 - product of (1 - c) over distinct sources: agreement raises the score.
    def combine(confidences)
      [1.0 - confidences.reduce(1.0) { |acc, c| acc * (1.0 - c) }, MAX_CONFIDENCE].min.round(4)
    end

    def rank_key(c)
      [Finding::SEVERITIES.index(c.severity), -c.confidence, -c.passes.size, c.file, c.line_start, c.title]
    end
  end
end
