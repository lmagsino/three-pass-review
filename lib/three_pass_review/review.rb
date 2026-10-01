# frozen_string_literal: true

module ThreePassReview
  # One review end to end: parse, plan under the cost ceiling, run the passes,
  # and account for what they cost. Used by the CLI and the eval.
  class Review
    Outcome = Data.define(:mode, :model, :diff, :plan, :result, :accounting, :max_cost_usd)

    def initialize(config:, client:, repo: ".", enforce_ceiling: true)
      @config = config
      @client = client
      @repo = repo
      @enforce = enforce_ceiling
    end

    def run(diff_text:, title: nil, body: nil, mode: "independent")
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
        passes: @config.enabled_passes, lines_around_hunk: @config.lines_around_hunk,
        reduced_lines_around_hunk: @config.reduced_lines_around_hunk)
      result = runner.run(plan.input, mode: mode, passes: plan.passes, guard: budget.guard)
      Outcome.new(mode: mode, model: @config.model, diff: diff, plan: plan, result: result,
        accounting: budget.account(result), max_cost_usd: @config.max_cost_usd)
    end

    private

    def empty_outcome(diff, mode, budget)
      result = RunResult.new(mode: mode, model: @config.model, pass_results: [].freeze)
      plan = Budget::Plan.new(input: nil, passes: [], estimate: Budget::Estimate.new(calls: [], total_usd: 0.0),
        degradations: [])
      Outcome.new(mode: mode, model: @config.model, diff: diff, plan: plan, result: result,
        accounting: budget.account(result), max_cost_usd: @config.max_cost_usd)
    end
  end
end
