# frozen_string_literal: true

module ThreePassReview
  module Formatters
    # Model output and diff paths are untrusted text headed for a PR comment.
    # Escape HTML so it can't add markup or a fake marker, and break up
    # @mentions so a prompt injection can't make the comment ping people.
    module Text
      ZERO_WIDTH_SPACE = "​"

      module_function

      # Also escapes the Markdown that could change the comment's structure:
      # backticks (a stray fence would swallow everything after it), links and
      # images, headings, and #123 references, which create backlinks.
      def block(text)
        text.to_s
          .gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          .gsub(/@(?=\w)/, "@#{ZERO_WIDTH_SPACE}")
          .gsub(/[`\[\]~]/) { |c| "\\#{c}" }
          .gsub(/#(?=\d)/, "##{ZERO_WIDTH_SPACE}")
          .gsub(/^(\s*)#/, "\\1\\#")
      end

      # One line, safe inside a table cell.
      def cell(text)
        block(text).gsub(/\s*\n\s*/, " ").gsub("|", "\\|").strip
      end

      def code_span(text)
        text = text.to_s.gsub(/\s*\n\s*/, " ")
        ticks = "`" * ((text.scan(/`+/).map(&:size).max || 0) + 1)
        pad = (text.start_with?("`") || text.end_with?("`")) ? " " : ""
        "#{ticks}#{pad}#{text}#{pad}#{ticks}"
      end

      def table_code(text)
        code_span(text).gsub("|", "\\|")
      end

      def fence(code)
        ticks = "`" * [3, (code.scan(/`+/).map(&:size).max || 0) + 1].max
        "#{ticks}\n#{code.chomp}\n#{ticks}"
      end

      def usd(amount)
        return "unknown" if amount.nil?
        return "$0" if amount.zero?
        return "<$0.001" if amount < 0.001

        format("$%.3f", amount)
      end

      def int(number)
        number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end
    end
  end
end
