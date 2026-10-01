# frozen_string_literal: true

module ThreePassReview
  module Formatters
    # The PR comment. The marker on the first line lets an integration find
    # and update its own comment.
    class Markdown
      MARKER = "<!-- threepass -->"
      ICONS = {"critical" => "🟥", "high" => "🔴", "medium" => "🟠", "low" => "🟡"}.freeze
      DEGRADATIONS = {
        "smaller_excerpts" => "file excerpts shrunk",
        "diff_only" => "reviewed from the diff alone",
        "skipped_architecture" => "architecture pass skipped"
      }.freeze

      def initialize(outcome)
        @outcome = outcome
        @reconciled = outcome.reconciled
      end

      def render
        parts = [MARKER, heading]
        parts << notes if notes
        if @reconciled.findings.any?
          parts << table
          parts << details
        end
        parts << footer
        "#{parts.join("\n\n")}\n"
      end

      private

      def findings = @reconciled.findings

      def heading
        return "### threepass: nothing to review" if @outcome.diff.empty?
        return "### threepass: no findings" if findings.empty?

        serious = %w[critical high].filter_map do |sev|
          n = findings.count { |f| f.severity == sev }
          "#{n} #{sev}" if n.positive?
        end
        noun = (findings.size == 1) ? "finding" : "findings"
        "### threepass: #{findings.size} #{noun}#{" (#{serious.join(", ")})" if serious.any?}"
      end

      def notes
        @notes ||= begin
          lines = @outcome.result.pass_results.reject(&:ok?).map do |r|
            if r.error.start_with?("skipped")
              "> ⚠️ The #{r.pass} pass was skipped to stay under the cost ceiling."
            else
              "> ⚠️ The #{source(r)} pass failed, so its findings are missing: #{Text.cell(r.error)}"
            end
          end
          if @outcome.plan.degradations.any?
            steps = @outcome.plan.degradations.map { |d| DEGRADATIONS.fetch(d) }.join("; ")
            lines << "> To stay under the #{Text.usd(@outcome.max_cost_usd)} cost ceiling: #{steps}."
          end
          if over_ceiling?
            lines << "> ⚠️ Actual cost #{Text.usd(@outcome.accounting.total_usd)} went over the " \
              "#{Text.usd(@outcome.max_cost_usd)} ceiling: the input estimate was too low."
          end
          lines.empty? ? nil : lines.join("\n")
        end
      end

      def over_ceiling?
        total = @outcome.accounting.total_usd
        total && total > @outcome.max_cost_usd
      end

      def table
        rows = findings.map do |f|
          "| #{ICONS[f.severity]} #{f.severity} | #{Text.cell(f.title)} | #{Text.table_code(f.location)} | " \
            "#{f.passes.join(", ")} | #{format("%.2f", f.confidence)} |"
        end
        ["| | Finding | Where | Passes | Confidence |", "|---|---|---|---|---|", *rows].join("\n")
      end

      def details
        items = findings.each_with_index.map do |f, i|
          evidence = f.evidence.map { |e| Text.fence(e) }.join("\n")
          [
            "**#{i + 1}. #{ICONS[f.severity]} #{Text.cell(f.title)}** #{Text.code_span(f.location)} · #{f.category}/#{Text.cell(f.subcategory)}",
            Text.block(f.explanation),
            evidence,
            "**Suggested fix:** #{Text.block(f.suggested_fix)}"
          ].join("\n\n")
        end
        "<details><summary>Details</summary>\n\n#{items.join("\n\n---\n\n")}\n\n</details>"
      end

      def footer
        acct = @outcome.accounting
        per_call = acct.calls.map { |c| "#{label(c.pass, c.sample)} #{Text.usd(c.cost_usd)}" }
        bits = ["Cost #{Text.usd(acct.total_usd)}#{" (#{per_call.join(" · ")})" if per_call.size > 1}"]
        bits << "#{Text.int(acct.input_tokens)} input / #{Text.int(acct.output_tokens)} output tokens"
        bits << "#{@reconciled.below_threshold} below threshold" if @reconciled.below_threshold.positive?
        bits << "#{@reconciled.cut} more not shown" if @reconciled.cut.positive?
        bits << "#{@reconciled.dropped_invalid} invalid dropped" if @reconciled.dropped_invalid.positive?
        bits << "model #{@outcome.model}"
        bits << "prompts #{Prompts.version}"
        "<sub>#{bits.join(" · ")}</sub>"
      end

      def source(result) = label(result.pass, result.sample)

      def label(pass, sample)
        sampled = @outcome.result.pass_results.count { |r| r.pass == pass } > 1
        sampled ? "#{pass}##{sample}" : pass
      end
    end
  end
end
