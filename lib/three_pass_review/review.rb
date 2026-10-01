# frozen_string_literal: true

module ThreePassReview
  # One review end to end: parse, plan under the cost ceiling, run the passes,
  # and account for what they cost. Used by the CLI and the eval.
  class Review
    Outcome = Data.define(:mode, :model, :diff, :plan, :result, :accounting, :reconciled, :max_cost_usd,
      :change_map, :brief, :brief_error)

    def initialize(config:, client:, repo: ".", enforce_ceiling: true)
      @config = config
      @client = client
      @repo = repo
      @enforce = enforce_ceiling
    end

    # brief: nil follows the config; true or false overrides it. The brief only
    # runs in independent mode.
    def run(diff_text:, title: nil, body: nil, mode: "independent", brief: nil)
      brief = @config.brief_enabled? if brief.nil?
      diff_text, title, body = [diff_text, title, body].map { |t| t&.dup&.force_encoding(Encoding::UTF_8)&.scrub }
      diff = Diff.parse(diff_text)
      budget = Budget.new(client: @client, max_cost_usd: @config.max_cost_usd, pricing: @config.pricing_for,
        enforce: @enforce)
      runner = Runner.new(client: @client, model: @config.model, max_output_tokens: @config.max_output_tokens,
        effort: @config.effort, samples: @config.samples)
      builder = ContextBuilder.new(repo: @repo, lines_around_hunk: @config.lines_around_hunk,
        max_excerpt_bytes: @config.max_excerpt_bytes, conventions: @config.conventions,
        max_conventions_bytes: @config.max_conventions_bytes)
      return empty_outcome(diff, mode, budget) if diff.empty?

      plan = budget.plan(builder: builder, diff: diff, title: title, body: body, runner: runner, mode: mode,
        passes: @config.enabled_passes + ((brief && mode == "independent") ? [Runner::BRIEF] : []),
        lines_around_hunk: @config.lines_around_hunk,
        reduced_lines_around_hunk: @config.reduced_lines_around_hunk)
      result = runner.run(plan.input, mode: mode, passes: plan.passes, guard: budget.guard)
      brief_result, brief_error = read_brief(result, diff)
      Outcome.new(mode: mode, model: @config.model, diff: diff, plan: plan, result: result,
        accounting: budget.account(result), reconciled: reconciler(diff).reconcile(result.pass_results),
        max_cost_usd: @config.max_cost_usd, change_map: ChangeMap.build(diff), brief: brief_result, brief_error: brief_error)
    end

    private

    def empty_outcome(diff, mode, budget)
      result = RunResult.new(mode: mode, model: @config.model, pass_results: [].freeze)
      plan = Budget::Plan.new(input: nil, passes: [], estimate: Budget::Estimate.new(calls: [], total_usd: 0.0),
        degradations: [])
      Outcome.new(mode: mode, model: @config.model, diff: diff, plan: plan, result: result,
        accounting: budget.account(result), reconciled: reconciler(diff).reconcile([]),
        max_cost_usd: @config.max_cost_usd, change_map: ChangeMap.build(diff), brief: nil, brief_error: nil)
    end

    # [brief, nil], [nil, reason], or [nil, nil] when no brief was asked for or
    # the ceiling dropped it.
    def read_brief(result, diff)
      run = result.pass_results.find { |r| r.pass == Runner::BRIEF }
      return [nil, nil] unless run
      return [nil, run.error] unless run.ok?

      Brief.from(run.data, diff: diff)
    end

    def reconciler(diff)
      Reconciler.new(diff: diff, confidence_threshold: @config.confidence_threshold,
        max_comments: @config.max_comments, merge_line_gap: @config.merge_line_gap)
    end
  end
end
