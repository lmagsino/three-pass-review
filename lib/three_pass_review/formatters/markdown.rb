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
        "skipped_architecture" => "architecture pass skipped",
        "skipped_brief" => "reviewer brief skipped"
      }.freeze
      # Change-map flags a deep reviewer should stop and look at.
      WARN_FLAGS = %w[migration dependencies ci infra deleted].freeze
      IMPACT_LABELS = {
        "behavior" => "Behavior", "api_contract" => "API or contract", "data" => "Data",
        "config" => "Config", "dependency" => "Dependencies", "security" => "Security", "performance" => "Performance"
      }.freeze
      LOOK_FIRST = 5

      def initialize(outcome)
        @outcome = outcome
        @reconciled = outcome.reconciled
      end

      def render
        return render_brief if brief_requested?

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

      def brief_requested?
        @outcome.result.pass_results.any? { |r| r.pass == Runner::BRIEF } ||
          @outcome.plan.degradations.include?("skipped_brief")
      end

      # The reviewer brief: orientation first, findings and a sign-off draft
      # folded below it.
      def render_brief
        brief = @outcome.brief
        parts = [MARKER, brief_heading]
        parts << notes if notes
        if brief.nil? && @outcome.brief_error && @outcome.result.pass_results.none? { |r| r.pass == Runner::BRIEF && !r.ok? }
          parts << "> ⚠️ The reviewer brief was unusable: #{Text.cell(@outcome.brief_error)}"
        end
        parts << "**The change.** #{Text.block(brief.summary)}" if brief
        parts << change_map
        if brief
          parts << bullets("What changed", brief.changes.map { |c| "#{Text.code_span(c["area"])}: #{Text.block(c["description"])}" })
          parts << bullets("Impact", brief.impact.map { |i| "**#{IMPACT_LABELS.fetch(i["kind"])}:** #{Text.block(i["description"])}" })
          parts << bullets("Risks", brief.risks.map { |r| Text.block(r) })
          parts << "**Rollback.** #{Text.block(brief.rollback)}" unless brief.rollback.empty?
          parts << tests_section(brief)
        end
        parts << look_first(brief)
        parts << bullets("Questions for the author", brief.questions.map { |q| Text.block(q) }) if brief
        parts << findings_section
        parts << sign_off(brief) if brief
        parts << footer
        "#{parts.compact.join("\n\n")}\n"
      end

      def brief_heading
        noun = (findings.size == 1) ? "finding" : "findings"
        serious = %w[critical high].filter_map do |sev|
          n = findings.count { |f| f.severity == sev }
          "#{n} #{sev}" if n.positive?
        end
        "### Review brief: #{findings.size} #{noun}#{" (#{serious.join(", ")})" if serious.any?}"
      end

      def bullets(title, items)
        return nil if items.empty?

        "**#{title}**\n\n#{items.map { |i| "- #{i}" }.join("\n")}"
      end

      def change_map
        map = @outcome.change_map
        rows = map.areas.map do |a|
          flags = a.flags.map { |f| WARN_FLAGS.include?(f) ? "⚠️ #{f}" : f }.join(", ")
          "| #{Text.table_code(a.name)} | #{a.files} | +#{a.added} −#{a.removed} | #{flags} |"
        end
        t = map.totals
        ["**Change map** <sub>(computed from the diff)</sub>", "",
          "| Area | Files | Lines | Flags |", "|---|---|---|---|", *rows, "",
          "#{t[:files]} #{(t[:files] == 1) ? "file" : "files"}, +#{t[:added]} −#{t[:removed]} lines."].join("\n")
      end

      def tests_section(brief)
        covered = brief.tests_covered.empty? ? ["none visible in the diff"] : brief.tests_covered
        lines = covered.map { |c| "- Covered: #{Text.block(c)}" } + brief.test_gaps.map { |g| "- Gap: #{Text.block(g)}" }
        "**Tests**\n\n#{lines.join("\n")}"
      end

      # The most serious findings first, then the brief's own suggestions
      # for lines no listed finding already covers.
      def look_first(brief)
        items = findings.reject { |f| f.severity == "low" }.first(3).map do |f|
          [f.file, f.line_start, f.line_end,
            "#{ICONS[f.severity]} #{f.severity} · #{Text.code_span(f.location)} · #{Text.cell(f.title)} _(#{f.passes.join(", ")})_"]
        end
        Array(brief&.review_order).each do |e|
          next if items.any? { |file, s, t, _| file == e["file"] && e["line_start"] <= t + 3 && s <= e["line_end"] + 3 }

          loc = (e["line_start"] == e["line_end"]) ? "#{e["file"]}:#{e["line_start"]}" : "#{e["file"]}:#{e["line_start"]}-#{e["line_end"]}"
          items << [e["file"], e["line_start"], e["line_end"], "#{Text.code_span(loc)} · #{Text.cell(e["why"])} _(brief)_"]
        end
        return nil if items.empty?

        "**Where to look first**\n\n#{items.first(LOOK_FIRST).each_with_index.map { |(*, text), i| "#{i + 1}. #{text}" }.join("\n")}"
      end

      def findings_section
        return "No findings above the confidence threshold." if findings.empty?

        "<details><summary>Findings (#{findings.size})</summary>\n\n#{table}\n\n#{details.delete_prefix("<details><summary>Details</summary>\n\n").delete_suffix("\n\n</details>")}\n\n</details>"
      end

      def sign_off(brief)
        body = ["Deep review",
          "- Verified: <how you checked the tests> (brief: #{brief.tests_covered.empty? ? "no tests visible" : brief.tests_covered.join("; ")})",
          "- Constraints: <the invariants you checked>",
          "- Rollback: #{brief.rollback.empty? ? "<how to undo this>" : brief.rollback}",
          *brief.questions.map { |q| "- Asked: #{q} -> <answer>" },
          "- Follow-ups: <issues filed, or none>"].map { |l| l.gsub(/\s*\n\s*/, " ") }.join("\n")
        "<details><summary>Sign-off draft</summary>\n\nCopy it into your approval and replace each <…>.\n\n#{Text.fence(body)}\n\n</details>"
      end

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
            if r.pass == Runner::BRIEF
              "> ⚠️ The reviewer brief didn't finish: #{Text.cell(r.error)}"
            elsif r.error.start_with?("skipped")
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
