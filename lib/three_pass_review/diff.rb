# frozen_string_literal: true

module ThreePassReview
  # Parses a unified diff (git or plain `diff -u`) into files and hunks, with
  # each line mapped to its old and new line numbers.
  class Diff
    class ParseError < Error; end

    Line = Data.define(:type, :text, :old_lineno, :new_lineno)

    Hunk = Data.define(:old_start, :old_count, :new_start, :new_count, :section, :lines) do
      # A pure deletion has no new lines; it is anchored at the line it follows.
      def new_range
        return (new_start..new_start) if new_count.zero?

        (new_start..(new_start + new_count - 1))
      end

      def added_linenos
        lines.select { |line| line.type == :add }.map(&:new_lineno)
      end
    end

    FileDiff = Data.define(:old_path, :new_path, :status, :binary, :hunks) do
      def path
        new_path || old_path
      end

      def deleted?
        status == :deleted
      end

      def binary?
        binary
      end

      def added_linenos
        hunks.flat_map(&:added_linenos)
      end

      def covers?(line_start, line_end, margin: 0)
        hunks.any? do |hunk|
          range = hunk.new_range
          line_start <= range.end + margin && line_end >= range.begin - margin
        end
      end
    end

    attr_reader :files, :text

    def self.parse(text)
      new(Parser.new(text).parse, text)
    end

    def initialize(files, text)
      @files = files.freeze
      @text = text.dup.freeze
      freeze
    end

    def file(path)
      files.find { |f| f.path == path }
    end

    def paths
      files.map(&:path)
    end

    def empty?
      files.empty?
    end

    class Parser
      HUNK_HEADER = /\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)\z/
      GIT_HEADER = %r{\Adiff --git (?:"?a/)(.+?)"? (?:"?b/)(.+?)"?\z}
      BINARY_LINE = /\ABinary files (.+) and (.+) differ\z/

      def initialize(text)
        @lines = text.to_s.lines.map { |l| l.chomp.delete_suffix("\r") }
        @files = []
        @current = nil
        @i = 0
      end

      def parse
        while @i < @lines.size
          line = @lines[@i]
          if line.start_with?("diff --git ")
            start_file
            if (m = GIT_HEADER.match(line))
              @current[:old_path] = @current[:git_old] = m[1]
              @current[:new_path] = @current[:git_new] = m[2]
            end
          elsif line.start_with?("--- ") && @lines[@i + 1]&.start_with?("+++ ")
            start_file if @current.nil? || @current[:hunks].any?
            @current[:old_path] = parse_path(line[4..])
            @current[:new_path] = parse_path(@lines[@i + 1][4..])
            @current[:explicit_paths] = true
            @i += 1
          elsif line.start_with?("@@ ")
            raise ParseError, "hunk before any file header at line #{@i + 1}" unless @current

            parse_hunk(line)
            next
          elsif @current
            parse_extended_header(line)
          end
          @i += 1
        end
        finish_file
        @files
      end

      private

      def start_file
        finish_file
        @current = {old_path: nil, new_path: nil, hunks: [], binary: false, flags: []}
      end

      def finish_file
        return unless @current

        c = @current
        @current = nil
        old_path = c[:old_path]
        new_path = c[:new_path]
        old_path = nil if c[:flags].include?(:new)
        new_path = nil if c[:flags].include?(:deleted)
        status =
          if old_path.nil? then :added
          elsif new_path.nil? then :deleted
          elsif c[:flags].include?(:renamed) || old_path != new_path then :renamed
          else :modified
          end
        @files << FileDiff.new(old_path: old_path&.freeze, new_path: new_path&.freeze, status: status,
          binary: c[:binary], hunks: c[:hunks].freeze)
      end

      def parse_extended_header(line)
        case line
        when /\Anew file mode/ then @current[:flags] << :new
        when /\Adeleted file mode/ then @current[:flags] << :deleted
        when /\Arename from (.+)\z/
          @current[:old_path] = unquote(Regexp.last_match(1))
          @current[:flags] << :renamed
        when /\Arename to (.+)\z/
          @current[:new_path] = unquote(Regexp.last_match(1))
          @current[:flags] << :renamed
        when "GIT binary patch" then @current[:binary] = true
        when BINARY_LINE
          @current[:binary] = true
          m = Regexp.last_match
          @current[:old_path] ||= parse_path(m[1])
          @current[:new_path] ||= parse_path(m[2])
        end
      end

      def parse_hunk(header)
        m = HUNK_HEADER.match(header) or raise ParseError, "malformed hunk header at line #{@i + 1}: #{header}"
        old_start = m[1].to_i
        old_count = m[2] ? m[2].to_i : 1
        new_start = m[3].to_i
        new_count = m[4] ? m[4].to_i : 1
        old_left = old_count
        new_left = new_count
        old_no = old_start
        new_no = new_start
        lines = []
        @i += 1

        while old_left.positive? || new_left.positive?
          raw = @lines[@i]
          raise ParseError, "hunk at line #{header} ends early" if raw.nil?

          marker = raw[0]
          text = (raw[1..] || "").freeze
          case marker
          when " ", nil
            raise ParseError, "hunk #{header} has more context than its header says" if old_left.zero? || new_left.zero?

            lines << Line.new(type: :context, text: text, old_lineno: old_no, new_lineno: new_no)
            old_no += 1
            new_no += 1
            old_left -= 1
            new_left -= 1
          when "-"
            raise ParseError, "hunk #{header} removes more lines than its header says" if old_left.zero?

            lines << Line.new(type: :del, text: text, old_lineno: old_no, new_lineno: nil)
            old_no += 1
            old_left -= 1
          when "+"
            raise ParseError, "hunk #{header} adds more lines than its header says" if new_left.zero?

            lines << Line.new(type: :add, text: text, old_lineno: nil, new_lineno: new_no)
            new_no += 1
            new_left -= 1
          when "\\"
            nil # "\ No newline at end of file" belongs to the previous line and isn't counted.
          else
            raise ParseError, "unexpected line inside hunk #{header}: #{raw}"
          end
          @i += 1
        end
        @i += 1 while @lines[@i]&.start_with?("\\")

        @current[:hunks] << Hunk.new(old_start: old_start, old_count: old_count, new_start: new_start,
          new_count: new_count, section: m[5].freeze, lines: lines.freeze)
      end

      def parse_path(raw)
        path = unquote(raw.split("\t", 2).first.strip)
        # The diff format's own token, not the OS null device; File::NULL is "NUL" on Windows.
        return nil if path == "/dev/null" # standard:disable Style/FileNull

        path.sub(%r{\A[ab]/}, "")
      end

      def unquote(path)
        return path unless path.start_with?('"') && path.end_with?('"')

        path[1..-2].gsub(/\\(["\\])/, '\1')
      end
    end
  end
end
