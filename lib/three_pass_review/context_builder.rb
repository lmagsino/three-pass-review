# frozen_string_literal: true

require "open3"

module ThreePassReview
  Excerpt = Data.define(:path, :start_line, :end_line, :text, :truncated)
  ConventionsFile = Data.define(:path, :text, :truncated)

  # The one input every pass receives. Built once and deep-frozen so no pass
  # can change what another pass sees.
  BaseInput = Data.define(:diff, :title, :body, :excerpts, :conventions, :lines_around_hunk, :omitted_excerpts) do
    def diff_text
      diff.text
    end

    def excerpts?
      !lines_around_hunk.nil?
    end
  end

  def self.deep_freeze(value)
    case value
    when Hash then value.each_value { |v| deep_freeze(v) }
    when Array then value.each { |v| deep_freeze(v) }
    when Data then value.to_h.each_value { |v| deep_freeze(v) }
    end
    value.freeze
  end

  def self.deep_frozen?(value)
    return false unless value.frozen?

    case value
    when Hash then value.each_value.all? { |v| deep_frozen?(v) }
    when Array then value.all? { |v| deep_frozen?(v) }
    when Data then value.to_h.each_value.all? { |v| deep_frozen?(v) }
    else true
    end
  end

  # Gathers context deterministically before any model call: excerpts of each
  # changed file around its hunks (head version), and the conventions files
  # the architecture pass judges against.
  class ContextBuilder
    DEFAULT_CONVENTIONS = %w[CLAUDE.md AGENTS.md CONVENTIONS.md .github/copilot-instructions.md].freeze

    def initialize(repo:, lines_around_hunk: 30, max_excerpt_bytes: 60_000,
      conventions: DEFAULT_CONVENTIONS, max_conventions_bytes: 20_000)
      @repo = File.realpath(repo)
      @tracked = tracked_files
      @lines_around_hunk = lines_around_hunk
      @max_excerpt_bytes = max_excerpt_bytes
      @conventions = conventions
      @max_conventions_bytes = max_conventions_bytes
    end

    # lines_around_hunk: nil sends the diff only: no excerpts, no conventions.
    def build(diff:, title: nil, body: nil, lines_around_hunk: @lines_around_hunk)
      diff_only = lines_around_hunk.nil?
      excerpts, omitted = diff_only ? [[], []] : build_excerpts(diff, lines_around_hunk)
      input = BaseInput.new(
        diff: diff,
        title: title.to_s.dup,
        body: body.to_s.dup,
        excerpts: excerpts,
        conventions: diff_only ? [] : load_conventions,
        lines_around_hunk: lines_around_hunk,
        omitted_excerpts: omitted
      )
      ThreePassReview.deep_freeze(input)
    end

    private

    def build_excerpts(diff, margin)
      budget = @max_excerpt_bytes
      excerpts = []
      omitted = []
      diff.files.each do |file|
        next if file.deleted? || file.binary? || file.hunks.empty?

        source = read_repo_file(file.path)
        next unless source

        file_lines = source.lines
        windows(file, margin, file_lines.size).each do |first, last|
          text = render(file, file_lines, first, last)
          if text.bytesize <= budget
            excerpts << Excerpt.new(path: file.path, start_line: first, end_line: last, text: text, truncated: false)
            budget -= text.bytesize
          elsif budget.positive? && (cut = truncate_lines(text, budget))
            shown = cut.lines.size - 1
            excerpts << Excerpt.new(path: file.path, start_line: first, end_line: first + shown - 1, text: cut, truncated: true)
            budget = 0
          else
            omitted << file.path
          end
        end
      end
      [excerpts, omitted.uniq]
    end

    # Hunk windows on the new file, widened by the margin and merged where
    # they touch.
    def windows(file, margin, line_count)
      return [] if line_count.zero?

      ranges = file.hunks.map do |hunk|
        r = hunk.new_range
        [[r.begin - margin, 1].max, [r.end + margin, line_count].min]
      end
      ranges.sort.each_with_object([]) do |(first, last), merged|
        if merged.any? && first <= merged.last[1] + 1
          merged.last[1] = [merged.last[1], last].max
        else
          merged << [first, last]
        end
      end
    end

    def render(file, file_lines, first, last)
      added = file.added_linenos.to_h { |n| [n, true] }
      width = last.to_s.size
      body = (first..last).map do |n|
        mark = added[n] ? "+" : " "
        "#{n.to_s.rjust(width)}#{mark}| #{file_lines[n - 1].chomp}\n"
      end
      "#{file.path} (lines #{first}-#{last}, + marks added lines)\n#{body.join}"
    end

    # Cuts at a line boundary; returns nil if not even the header and one line fit.
    def truncate_lines(text, limit)
      kept = +""
      text.each_line do |line|
        break if kept.bytesize + line.bytesize > limit

        kept << line
      end
      (kept.lines.size >= 2) ? kept : nil
    end

    def load_conventions
      budget = @max_conventions_bytes
      @conventions.filter_map do |path|
        text = read_repo_file(path)
        next unless text && budget.positive?

        truncated = text.bytesize > budget
        text = text.byteslice(0, budget).scrub("") if truncated
        budget -= text.bytesize
        ConventionsFile.new(path: path, text: text, truncated: truncated)
      end
    end

    # Paths come from an untrusted diff or config. Never follow a symlink, even
    # one inside the repo: a PR can add `notes.txt -> .env` and have the secret
    # excerpted. Never read .git/, and in a git checkout read tracked files only.
    def read_repo_file(relative)
      return nil unless relative.is_a?(String) && !relative.empty? && !relative.include?("\0")
      return nil if relative.start_with?("/") || relative.split("/").include?(".git")

      expanded = File.expand_path(relative, @repo)
      return nil unless expanded.start_with?(@repo + File::SEPARATOR)
      return nil unless File.file?(expanded) && File.realpath(expanded) == expanded
      return nil if @tracked && !@tracked.include?(expanded.delete_prefix(@repo + File::SEPARATOR))

      text = File.read(expanded, mode: "rb")
      return nil if text.include?("\0")

      text.force_encoding(Encoding::UTF_8).scrub
    rescue SystemCallError
      nil
    end

    # nil when the repo isn't a git checkout (eval context directories).
    def tracked_files
      return nil unless File.exist?(File.join(@repo, ".git"))

      out, status = Open3.capture2("git", "-C", @repo, "ls-files", "-z")
      status.success? ? out.split("\0").to_set : nil
    rescue SystemCallError
      nil
    end
  end
end
