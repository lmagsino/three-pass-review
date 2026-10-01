# frozen_string_literal: true

require "json"

module ThreePassReview
  module Formatters
    # Machine-readable output, used by the eval.
    class JSON
      SCHEMA_VERSION = 1

      def initialize(outcome)
        @outcome = outcome
      end

      def render
        "#{::JSON.pretty_generate(to_h)}\n"
      end

      def to_h
        o = @outcome
        r = o.reconciled
        {
          "schema_version" => SCHEMA_VERSION,
          "tool_version" => VERSION,
          "mode" => o.mode,
          "model" => o.model,
          "prompts" => {"version" => Prompts.version, "hashes" => Prompts.hashes},
          "findings" => r.findings.map { |f| finding(f) },
          "counts" => {
            "reported" => r.findings.size, "below_threshold" => r.below_threshold,
            "cut" => r.cut, "dropped_invalid" => r.dropped_invalid
          },
          "invalid" => r.invalid.map { |i| {"source" => i.source, "reason" => i.reason} },
          "passes" => o.result.pass_results.zip(o.accounting.calls).map { |pr, cost| pass(pr, cost) },
          "cost" => {
            "total_usd" => o.accounting.total_usd, "estimated_usd" => o.plan.estimate.total_usd,
            "max_cost_usd" => o.max_cost_usd, "input_tokens" => o.accounting.input_tokens,
            "output_tokens" => o.accounting.output_tokens,
            "over_ceiling" => !o.accounting.total_usd.nil? && o.accounting.total_usd > o.max_cost_usd
          },
          "degradations" => o.plan.degradations,
          "change_map" => o.change_map&.to_h,
          "brief" => o.brief&.to_h&.transform_keys(&:to_s),
          "brief_error" => o.brief_error,
          "diff" => {"files" => o.diff.paths}
        }
      end

      private

      def finding(f)
        f.to_h.transform_keys(&:to_s).merge("location" => f.location)
      end

      def pass(result, cost)
        status = if result.ok? then "ok"
        elsif result.error.start_with?("skipped") then "skipped"
        else "failed"
        end
        {
          "pass" => result.pass, "sample" => result.sample, "status" => status, "error" => result.error,
          "stop_reason" => result.stop_reason, "input_tokens" => result.input_tokens,
          "output_tokens" => result.output_tokens, "cost_usd" => cost.cost_usd, "raw_findings" => result.findings
        }
      end
    end
  end
end
