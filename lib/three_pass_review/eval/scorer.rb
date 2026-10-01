# frozen_string_literal: true

module ThreePassReview
  module Eval
    # Turns raw run records into the metrics in docs/eval-design.md. Used by
    # eval:run and again by eval:report, so precision always reflects the
    # latest labels.
    #
    # A defect counts as caught when it's caught in a majority of the runs of
    # its case. That keeps n equal to the number of defects, so the Wilson
    # interval means what it says; per-run recall is reported as stability.
    class Scorer
      THRESHOLDS = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9].freeze
      MAX_UNLABELED_SHARE = 0.05
      SMALL_N = 8

      def initialize(cases:, records:, labels:, runs:, gap: 3, max_comments: 10, training_cutoff: nil)
        @cases = cases.to_h { |c| [c.id, c] }
        missing = records.map { |r| r["case"] }.uniq - @cases.keys
        raise Error, "records name cases that aren't in the dataset: #{missing.join(", ")}" if missing.any?

        # A review that errored produced nothing; it counts as a miss for
        # recall, like a refused one.
        @records = records.map { |r| r["error"] ? r.merge("refused" => true) : r }
        @labels = labels
        @runs = runs
        @matcher = Matcher.new(gap: gap)
        @gap = gap
        @max_comments = max_comments
        @training_cutoff = training_cutoff
      end

      def score
        reconciled = @records.map { |r| [r, findings(r)] }
        {
          "cases" => case_counts,
          "reviews" => @records.size,
          "recall" => recall(reconciled),
          "precision" => precision(reconciled),
          "per_pass" => per_pass,
          "cost_usd" => cost,
          "ceiling_hits" => Metrics.proportion(@records.count { |r| r["refused"] || degraded?(r) }, @records.size),
          "refused" => @records.count { |r| r["refused"] },
          "latency_s" => {"median" => Metrics.percentile(latencies, 50), "p90" => Metrics.percentile(latencies, 90)},
          "threshold_sweep" => threshold_sweep,
          "misses" => misses(reconciled)
        }
      end

      # Every unmatched finding, reconciled and per pass, for the labels file.
      def label_entries
        entries = {}
        @records.each do |record|
          kase = @cases.fetch(record["case"])
          sources = [["reconciled", findings(record)], ["sweep", sweep_findings(record, kase, THRESHOLDS.min, nil)]] +
            pass_findings(record).map { |pass, list| ["pass:#{pass}", list] }
          sources.each do |from, list|
            unmatched(kase, list).each do |f|
              key = Labels.key(kase.id, f)
              entry = entries[key] ||= {"key" => key, "case" => kase.id, "file" => f["file"],
                                        "lines" => [f["line_start"], f["line_end"]], "title" => f["title"], "from" => []}
              entry["from"] |= [from]
            end
          end
        end
        entries.values
      end

      private

      def findings(record)
        record.dig("output", "findings") || []
      end

      def degraded?(record)
        Array(record.dig("output", "degradations")).any?
      end

      def case_counts
        kinds = @cases.values.group_by(&:kind).transform_values(&:size)
        {"total" => @cases.size, "real" => kinds["real"].to_i, "planted" => kinds["planted"].to_i,
         "clean" => kinds["clean"].to_i, "defects" => @cases.values.sum { |c| c.defects.size }}
      end

      def records_for(kase)
        @records.select { |r| r["case"] == kase.id }
      end

      # caught_in[defect] = number of runs that caught it, under the matcher.
      def caught_counts(per_record_findings, mode)
        counts = Hash.new(0)
        per_record_findings.each do |record, list|
          kase = @cases.fetch(record["case"])
          @matcher.public_send(mode, list, kase.defects).caught.each { |id| counts[[kase.id, id]] += 1 }
        end
        counts
      end

      def all_defects
        @cases.values.flat_map { |c| c.defects.map { |d| [c, d] } }
      end

      def majority?(count)
        count > @runs / 2.0
      end

      def recall(reconciled, defects: all_defects)
        strict = caught_counts(reconciled, :strict)
        lenient = caught_counts(reconciled, :lenient)
        caught = ->(counts, list) { list.count { |c, d| majority?(counts[[c.id, d.id]]) } }
        result = {
          "strict" => Metrics.proportion(caught.call(strict, defects), defects.size),
          "lenient" => Metrics.proportion(caught.call(lenient, defects), defects.size),
          "by_category" => grouped(defects, strict) { |_, d| d.category },
          "by_subcategory" => grouped(defects, strict) { |_, d| d.subcategory },
          "stability" => stability(reconciled, defects)
        }
        if @training_cutoff
          result["by_cutoff"] = grouped(defects, strict) { |c, _| (c.merged_at && c.merged_at > @training_cutoff) ? "after" : "before" }
        end
        result
      end

      # Small groups are counts, never percentages.
      def grouped(defects, counts)
        defects.group_by { |c, d| yield(c, d) }.sort.to_h do |name, list|
          k = list.count { |c, d| majority?(counts[[c.id, d.id]]) }
          [name, (list.size < SMALL_N) ? {"k" => k, "n" => list.size, "text" => "#{k} of #{list.size}"} : Metrics.proportion(k, list.size)]
        end
      end

      def stability(reconciled, defects)
        return nil if defects.empty?

        rates = (1..@runs).map do |run|
          caught = reconciled.select { |r, _| r["run"] == run }.sum do |record, list|
            kase = @cases.fetch(record["case"])
            ids = defects.select { |c, _| c.id == kase.id }.map { |_, d| d.id }
            (@matcher.strict(list, kase.defects).caught & ids).size
          end
          caught.to_f / defects.size
        end
        {"min" => rates.min, "max" => rates.max, "per_run" => rates}
      end

      def unmatched(kase, list)
        matched = @matcher.lenient(list, kase.defects).matched_findings
        list.each_index.reject { |i| matched.include?(i) }.map { |i| list[i] }
      end

      # Precision = (matched + real) / (all - unclear). Matched is lenient:
      # a finding on the defect's lines is a real problem even if its
      # category differs. Refused while more than 5% of findings are unlabeled.
      def precision(per_record_findings)
        total = matched = 0
        tally = Hash.new(0)
        fp_clean = 0
        per_record_findings.each do |record, list|
          kase = @cases.fetch(record["case"])
          total += list.size
          matched += @matcher.lenient(list, kase.defects).matched_findings.size
          unmatched(kase, list).each do |f|
            label = @labels.label(Labels.key(kase.id, f))
            tally[label] += 1
            fp_clean += 1 if label == "false_positive" && kase.kind == "clean"
          end
        end
        clean_reviews = per_record_findings.count { |r, _| @cases.fetch(r["case"]).kind == "clean" }
        share = total.zero? ? 0.0 : tally["unlabeled"].to_f / total
        verified = share <= MAX_UNLABELED_SHARE
        denominator = total - tally["unclear"]
        {
          "findings" => total, "matched" => matched, "labels" => tally,
          "unlabeled_share" => share,
          "value" => verified ? Metrics.proportion(matched + tally["real"], denominator) : nil,
          "false_positives_per_clean_pr" => (verified && clean_reviews.positive?) ? {"value" => fp_clean.to_f / clean_reviews, "n" => clean_reviews} : nil,
          "unverified_per_pr" => per_record_findings.empty? ? nil : tally["unlabeled"].to_f / per_record_findings.size
        }
      end

      def pass_findings(record)
        kase = @cases.fetch(record["case"])
        Array(record.dig("output", "passes")).each_with_object({}) do |pass, out|
          name = (record.dig("output", "passes").count { |p| p["pass"] == pass["pass"] } > 1) ? "#{pass["pass"]}##{pass["sample"]}" : pass["pass"]
          out[name] = Array(pass["raw_findings"]).filter_map do |raw|
            finding, = Finding.validate(raw, diff: kase.diff, pass: pass["pass"])
            finding&.to_h&.transform_keys(&:to_s)
          end
        end
      end

      def per_pass
        names = @records.flat_map { |r| pass_findings(r).keys }.uniq
        names.to_h do |name|
          per_record = @records.map { |r| [r, pass_findings(r).fetch(name, [])] }
          category = Finding::CATEGORIES.include?(name) ? name : nil
          own = category ? all_defects.select { |_, d| d.category == category } : all_defects
          costs = @records.map do |r|
            passes = Array(r.dig("output", "passes"))
            passes.select { |p| [p["pass"], "#{p["pass"]}##{p["sample"]}"].include?(name) }.sum { |p| p["cost_usd"].to_f }
          end
          [name, {
            "recall_own_category" => recall(per_record, defects: own).slice("strict", "lenient"),
            "recall_all" => recall(per_record).slice("strict", "lenient", "by_category"),
            "precision" => precision(per_record),
            "cost_usd" => {"median" => Metrics.percentile(costs, 50), "p90" => Metrics.percentile(costs, 90)}
          }]
        end
      end

      def cost
        totals = @records.map { |r| r.dig("output", "cost", "total_usd") }.compact
        {"median" => Metrics.percentile(totals, 50), "p90" => Metrics.percentile(totals, 90), "max" => totals.max, "n" => totals.size}
      end

      def latencies
        @records.map { |r| r["latency_s"] }
      end

      # Re-reconciles the raw pass findings at each threshold.
      def threshold_sweep
        THRESHOLDS.to_h do |t|
          per_record = @records.reject { |r| r["refused"] }.map do |record|
            [record, sweep_findings(record, @cases.fetch(record["case"]), t, @max_comments)]
          end
          strict = caught_counts(per_record, :strict)
          [t.to_s, {
            "recall" => Metrics.proportion(all_defects.count { |c, d| majority?(strict[[c.id, d.id]]) }, all_defects.size),
            "precision" => precision(per_record)["value"]
          }]
        end
      end

      # Raw pass findings reconciled again at another threshold. With no cap
      # at the lowest threshold this is a superset of every sweep point, which
      # is what the labels file needs.
      def sweep_findings(record, kase, threshold, cap)
        results = Array(record.dig("output", "passes")).map do |p|
          PassResult.new(pass: p["pass"], sample: p["sample"], findings: Array(p["raw_findings"]), input_tokens: 0,
            output_tokens: 0, stop_reason: nil, error: p["error"])
        end
        Reconciler.new(diff: kase.diff, confidence_threshold: threshold, max_comments: cap || (1 << 30),
          merge_line_gap: @gap).reconcile(results).findings.map { |f| f.to_h.transform_keys(&:to_s) }
      end

      def misses(reconciled)
        strict = caught_counts(reconciled, :strict)
        all_defects.reject { |c, d| majority?(strict[[c.id, d.id]]) }.map do |c, d|
          {"case" => c.id, "defect" => d.id, "category" => d.category, "subcategory" => d.subcategory,
           "description" => d.description, "caught_in_runs" => strict[[c.id, d.id]]}
        end
      end
    end
  end
end
