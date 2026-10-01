# frozen_string_literal: true

require "test_helper"

class ReviewTest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")
  REPO = File.join(FIXTURES, "repo")

  def review(config = ThreePassReview::Config.new, client: ThreePassReview::LLM::FakeClient.new(BASIC), **opts)
    ThreePassReview::Review.new(config: config, client: client, repo: REPO, **opts)
  end

  def test_runs_end_to_end_under_the_default_ceiling
    outcome = review.run(diff_text: fixture_diff.text, title: "Add sorting", body: "Sorts invoices.")

    assert_equal %w[correctness security architecture], outcome.result.pass_results.map(&:pass)
    assert_empty outcome.plan.degradations
    assert_operator outcome.accounting.total_usd, :>, 0
    assert_operator outcome.plan.estimate.total_usd, :<=, 0.50
  end

  def test_disabled_passes_from_config_are_not_run
    config = ThreePassReview::Config.new("passes" => {"architecture" => {"enabled" => false}})
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    review(config, client: client).run(diff_text: fixture_diff.text)

    assert_equal %w[correctness security], client.requests.map(&:pass).sort
  end

  def test_empty_diff_makes_no_calls
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    outcome = review(client: client).run(diff_text: "")

    assert_empty client.requests
    assert_in_delta 0.0, outcome.accounting.total_usd
  end

  def test_invalid_utf8_in_the_diff_is_scrubbed
    text = fixture_diff.text.sub("customer.credit", "customer.cr\xE9dit".b)
    outcome = review.run(diff_text: text.b, title: "caf\xE9".b)

    assert_equal 3, outcome.result.pass_results.size
    JSON.generate(ThreePassReview::Formatters::JSON.new(outcome).to_h)
  end

  def test_unpriced_model_refuses_unless_the_ceiling_is_off
    config = ThreePassReview::Config.new("model" => "claude-unpriced")

    assert_raises(ThreePassReview::Budget::Refused) { review(config).run(diff_text: fixture_diff.text) }
    outcome = review(config, enforce_ceiling: false).run(diff_text: fixture_diff.text)
    assert_nil outcome.accounting.total_usd
  end
end
