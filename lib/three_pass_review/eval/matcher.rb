# frozen_string_literal: true

module ThreePassReview
  module Eval
    # Matches findings to known defects. Strict: same file, lines overlapping
    # within the gap, same category. Lenient: file and lines only. A finding
    # matches at most one defect and a defect is caught at most once; findings
    # are taken in the order given, which is the reviewer's own ranking.
    class Matcher
      Match = Data.define(:caught, :matched_findings)

      def initialize(gap: 3)
        @gap = gap
      end

      def strict(findings, defects)
        match(findings, defects, category: true)
      end

      def lenient(findings, defects)
        match(findings, defects, category: false)
      end

      private

      def match(findings, defects, category:)
        caught = {}
        matched = []
        findings.each_with_index do |f, i|
          defect = defects.find { |d| !caught.key?(d.id) && hit?(f, d, category) }
          next unless defect

          caught[defect.id] = i
          matched << i
        end
        Match.new(caught: caught.keys, matched_findings: matched)
      end

      def hit?(finding, defect, category)
        return false unless finding["file"] == defect.file
        return false unless finding["line_start"] <= defect.line_end + @gap && defect.line_start <= finding["line_end"] + @gap

        !category || finding["category"] == defect.category
      end
    end
  end
end
