# frozen_string_literal: true

require "test_helper"

class BudgetTest < Minitest::Test
  PRICING = {input: 2.0, output: 10.0}
  REPO = File.join(FIXTURES, "repo")

  # Bills every call at the worst case the estimate allows for: the input
  # the estimate counted, and the full max_tokens of output.
  class WorstCaseClient < ThreePassReview::LLM::Client
    attr_reader :requests

    def initialize
      super
      @requests = Queue.new
    end

    def complete(request)
      @requests << request
      ThreePassReview::LLM::Response.new(data: {"findings" => []}, input_tokens: (request.chars / 3.5).ceil,
        output_tokens: request.max_tokens, stop_reason: "end_turn", error: nil)
    end
  end

  def budget(client: WorstCaseClient.new, max: 1.0, pricing: PRICING, enforce: true)
    ThreePassReview::Budget.new(client: client, max_cost_usd: max, pricing: pricing, enforce: enforce)
  end

  def runner(client = WorstCaseClient.new)
    ThreePassReview::Runner.new(client: client, model: "claude-sonnet-5-5", max_output_tokens: 4000)
  end

  def builder
    ThreePassReview::ContextBuilder.new(repo: REPO, lines_around_hunk: 30)
  end

  def plan(b, mode: "independent", passes: ThreePassReview::Runner::PASS_ORDER)
    b.plan(builder: builder, diff: fixture_diff, title: "t", body: "b", runner: runner, mode: mode, passes: passes,
      lines_around_hunk: 30, reduced_lines_around_hunk: 5)
  end

  def step_costs(mode: "independent")
    b = budget
    full = builder.build(diff: fixture_diff, title: "t", body: "b")
    small = builder.build(diff: fixture_diff, title: "t", body: "b", lines_around_hunk: 5)
    bare = builder.build(diff: fixture_diff, title: "t", body: "b", lines_around_hunk: nil)
    passes = ThreePassReview::Runner::PASS_ORDER
    [
      b.estimate(runner, full, mode: mode, passes: passes),
      b.estimate(runner, small, mode: mode, passes: passes),
      b.estimate(runner, bare, mode: mode, passes: passes),
      b.estimate(runner, bare, mode: mode, passes: passes - ["architecture"])
    ].map(&:total_usd)
  end

  def test_cost_uses_per_million_rates
    assert_in_delta 0.052, budget.cost(1_000, 5_000)
  end

  def test_estimate_prices_output_at_max_tokens_and_counts_input_with_the_api
    client = ThreePassReview::LLM::FakeClient.new(nil, token_count: 1_000)
    est = budget(client: client).estimate(runner, base_input, mode: "independent", passes: %w[security])

    call = est.calls.first
    assert_equal [1_000, 4_000, :count_tokens], [call.input_tokens, call.output_tokens, call.counted_by]
    assert_in_delta (1_000 * 2.0 + 4_000 * 10.0) / 1_000_000, est.total_usd
  end

  def test_estimate_falls_back_to_characters_over_three_and_a_half
    est = budget.estimate(runner, base_input, mode: "independent", passes: %w[security])
    request = runner.planned_requests(base_input, mode: "independent", passes: %w[security]).first.first

    assert_equal [(request.chars / 3.5).ceil, :chars], [est.calls.first.input_tokens, est.calls.first.counted_by]
  end

  def test_chained_estimate_allows_for_earlier_findings
    plain = budget.estimate(runner, base_input, mode: "independent", passes: ThreePassReview::Runner::PASS_ORDER)
    chained = budget.estimate(runner, base_input, mode: "chained", passes: ThreePassReview::Runner::PASS_ORDER)

    assert_equal [0, 4_000, 8_000], chained.calls.zip(plain.calls).map { |c, p| c.input_tokens - p.input_tokens }
  end

  def test_steps_get_cheaper_in_the_documented_order
    costs = step_costs

    assert_equal costs.sort.reverse, costs
    assert_equal costs.uniq, costs
  end

  def test_degradation_order
    full, small, bare, two_passes = step_costs

    assert_equal [[], 3], plan_shape(budget(max: full))
    assert_equal [%w[smaller_excerpts], 3], plan_shape(budget(max: (full + small) / 2))
    assert_equal [%w[smaller_excerpts diff_only], 3], plan_shape(budget(max: (small + bare) / 2))
    assert_equal [%w[smaller_excerpts diff_only skipped_architecture], 2], plan_shape(budget(max: (bare + two_passes) / 2))

    error = assert_raises(ThreePassReview::Budget::Refused) { plan(budget(max: two_passes / 2)) }
    assert_equal %w[smaller_excerpts diff_only skipped_architecture], error.degradations
    assert_match(/over max_cost_usd/, error.message)
  end

  def plan_shape(b)
    p = plan(b)
    [p.degradations, p.passes.size]
  end

  def test_smaller_excerpts_keep_excerpts_and_diff_only_drops_them
    full, small, = step_costs

    assert_equal 5, plan(budget(max: (full + small) / 2)).input.lines_around_hunk
    assert_empty plan(budget(max: small - 0.0001)).input.excerpts
  end

  def test_single_modes_cannot_skip_a_pass
    b = budget(max: 0.0001)

    error = assert_raises(ThreePassReview::Budget::Refused) { plan(b, mode: "single_sampled") }
    assert_equal %w[smaller_excerpts diff_only], error.degradations
  end

  def test_missing_pricing_refuses
    error = assert_raises(ThreePassReview::Budget::Refused) { budget(pricing: nil) }
    assert_match(/--no-cost-ceiling/, error.message)
  end

  def test_no_cost_ceiling_runs_without_pricing_and_reports_no_cost
    b = budget(pricing: nil, enforce: false, max: 0.0001)
    p = plan(b)

    assert_empty p.degradations
    assert_nil p.estimate.total_usd
  end

  def test_the_ceiling_is_never_exceeded
    outcomes = Hash.new(0)
    # A grid of ceilings, plus the midpoints between degradation steps so
    # every step is exercised.
    full, small, bare, two_passes = step_costs
    ceilings = (1..40).map { |i| i * 0.005 } + [(full + small) / 2, (small + bare) / 2, (bare + two_passes) / 2]
    ceilings.each do |max|
      %w[independent chained single single_sampled].each do |mode|
        client = WorstCaseClient.new
        config = ThreePassReview::Config.new("max_cost_usd" => max)
        outcome = ThreePassReview::Review.new(config: config, client: client, repo: REPO)
          .run(diff_text: fixture_diff.text, title: "t", body: "b", mode: mode)

        assert_operator outcome.accounting.total_usd, :<=, max, "#{mode} at $#{max} spent #{outcome.accounting.total_usd}"
        outcomes[outcome.plan.degradations.last || "none"] += 1
      rescue ThreePassReview::Budget::Refused
        assert_empty client.requests, "#{mode} at $#{max} refused after calling the API"
        outcomes["refused"] += 1
      end
    end

    assert_equal %w[diff_only none refused skipped_architecture smaller_excerpts], outcomes.keys.sort
  end

  def test_chained_guard_skips_a_call_that_would_go_over
    pricey = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "correctness" => {"findings" => [], "usage" => {"input_tokens" => 210_000, "output_tokens" => 4_000}},
      "security" => {"findings" => []}, "architecture" => {"findings" => []}
    })
    b = budget(client: pricey, max: 0.5)
    result = runner(pricey).run(base_input, mode: "chained", guard: b.guard)

    assert_equal %w[correctness], pricey.requests.map(&:pass)
    assert_equal ["skipped: would go over max_cost_usd"] * 2, result.pass_results.drop(1).map(&:error)
    assert_operator b.account(result).total_usd, :<=, 0.5
  end

  def test_actual_cost_comes_from_reported_usage
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "security" => {"findings" => [], "usage" => {"input_tokens" => 1_000, "output_tokens" => 200}}
    })
    acct = budget.account(runner(client).run(base_input, passes: %w[security]))

    assert_in_delta 0.004, acct.total_usd
    assert_equal [1_000, 200], [acct.input_tokens, acct.output_tokens]
    assert_equal :usage, acct.calls.first.counted_by
  end
end
