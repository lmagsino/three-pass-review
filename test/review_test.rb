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

  def test_brief_runs_only_when_asked_and_only_in_independent_mode
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    plain = review(client: client).run(diff_text: fixture_diff.text)
    assert_nil plain.brief
    refute_includes client.requests.map(&:pass), "brief"

    with_brief = review.run(diff_text: fixture_diff.text, brief: true)
    assert_match(/Adds sorting/, with_brief.brief.summary)
    assert_operator with_brief.change_map.areas.size, :>=, 1

    chained = review.run(diff_text: fixture_diff.text, mode: "chained", brief: true)
    assert_nil chained.brief
  end

  def test_a_failed_brief_is_reported_and_the_findings_still_come_back
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "correctness" => {"findings" => []}, "security" => {"findings" => []}, "architecture" => {"findings" => []},
      "brief" => {"error" => "output cut off at max_output_tokens (4000); raise it"}
    })
    outcome = review(client: client).run(diff_text: fixture_diff.text, brief: true)

    assert_nil outcome.brief
    assert_match(/cut off/, outcome.brief_error)
    assert_equal 4, outcome.result.pass_results.size
  end
end
