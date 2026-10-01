# frozen_string_literal: true

require "test_helper"

class RunnerTest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")

  def runner(client, **opts)
    ThreePassReview::Runner.new(client: client, model: "claude-sonnet-5-5", max_output_tokens: 4000, **opts)
  end

  def test_independent_runs_the_three_passes_once_each
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    result = runner(client).run(base_input)

    assert_equal "independent", result.mode
    assert_equal %w[architecture correctness security], client.requests.map(&:pass).sort
    assert_equal %w[correctness security architecture], result.pass_results.map(&:pass)
    assert result.pass_results.all?(&:ok?)
    assert_equal 3, result.pass_results.find { |r| r.pass == "correctness" }.findings.size
  end

  def test_independent_passes_run_concurrently
    barrier = Queue.new
    arrived = Thread::Queue.new
    wait_for_all = lambda do |_request|
      arrived << 1
      barrier.pop(timeout: 2) || raise("passes did not run concurrently")
    end
    client = ThreePassReview::LLM::FakeClient.new(BASIC, on_complete: wait_for_all)
    releaser = Thread.new do
      3.times { arrived.pop(timeout: 2) }
      3.times { barrier << :go }
    end
    result = runner(client).run(base_input)
    releaser.join

    assert result.pass_results.all?(&:ok?), result.pass_results.map(&:error).inspect
  end

  def test_chained_runs_in_order_and_feeds_earlier_findings_forward
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    runner(client).run(base_input, mode: "chained")
    correctness, security, architecture = client.requests

    assert_equal %w[correctness security architecture], client.requests.map(&:pass)
    refute_includes correctness.user, "earlier_findings"
    assert_includes security.user, "earlier_findings_from_correctness"
    refute_includes security.user, "earlier_findings_from_security"
    assert_includes architecture.user, "earlier_findings_from_correctness"
    assert_includes architecture.user, "earlier_findings_from_security"
    assert_includes architecture.user, "Nil customer not handled in total_due"
  end

  def test_single_sends_one_combined_request
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    result = runner(client).run(base_input, mode: "single")

    assert_equal %w[combined], client.requests.map(&:pass)
    assert_equal %w[correctness security architecture], client.requests.first.schema.dig(:properties, :findings, :items, :properties, :category, :enum)
    assert_equal 2, result.pass_results.first.findings.size
  end

  def test_single_sampled_sends_identical_combined_requests
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    result = runner(client, samples: 3).run(base_input, mode: "single_sampled")

    assert_equal %w[combined] * 3, client.requests.map(&:pass)
    assert_equal 1, client.requests.uniq.size
    assert_equal [1, 2, 3], result.pass_results.map(&:sample).sort
  end

  def test_disabled_passes_are_not_sent
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    runner(client).run(base_input, passes: %w[security correctness])

    assert_equal %w[correctness security], client.requests.map(&:pass).sort
  end

  def test_requests_carry_model_limits_and_effort
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    runner(client, effort: "medium").run(base_input)

    client.requests.each do |req|
      assert_equal ["claude-sonnet-5-5", 4000, "medium"], [req.model, req.max_tokens, req.effort]
    end
  end

  def test_a_failing_pass_does_not_stop_the_others
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "correctness" => {"findings" => []}, "architecture" => {"findings" => []},
      "security" => {"error" => "output cut off", "stop_reason" => "max_tokens", "usage" => {"input_tokens" => 10, "output_tokens" => 4000}}
    })
    results = runner(client).run(base_input).pass_results.to_h { |r| [r.pass, r] }

    assert results["correctness"].ok?
    refute results["security"].ok?
    assert_equal 4000, results["security"].output_tokens
  end

  def test_client_exceptions_become_pass_errors
    client = Object.new
    def client.complete(_) = raise(IOError, "connection reset")
    results = runner(client).run(base_input).pass_results

    assert results.all? { |r| r.error == "IOError: connection reset" }
  end

  def test_reply_without_a_findings_list_is_an_error
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {"security" => {"findings" => nil}})
    result = runner(client).run(base_input, passes: %w[security])

    assert_equal "reply had no findings list", result.pass_results.first.error
  end

  def test_rejects_unknown_modes_and_unfrozen_input
    client = ThreePassReview::LLM::FakeClient.new(BASIC)

    assert_raises(ArgumentError) { runner(client).run(base_input, mode: "debate") }
    unfrozen = base_input.then { |i| i.class.new(**i.to_h, excerpts: i.excerpts.dup) }
    assert_raises(ArgumentError) { runner(client).run(unfrozen) }
  end

  def test_diff_only_input_tells_the_model_excerpts_were_left_out
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    runner(client).run(base_input(lines_around_hunk: nil), passes: %w[security])

    assert_includes client.requests.first.user, "Excerpts were left out"
    refute_includes client.requests.first.user, "file_excerpts"
  end

  def test_the_brief_runs_alongside_the_checks_in_independent_mode
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    result = runner(client).run(base_input, passes: %w[correctness security architecture brief])
    brief = result.pass_results.find { |r| r.pass == "brief" }

    assert_equal %w[architecture brief correctness security], client.requests.map(&:pass).sort
    assert brief.ok?
    assert_empty brief.findings
    assert_match(/Adds sorting/, brief.data["summary"])
    assert_equal ThreePassReview::Brief.schema, client.requests.find { |r| r.pass == "brief" }.schema
  end

  def test_the_brief_is_only_for_independent_mode
    client = ThreePassReview::LLM::FakeClient.new(BASIC)

    %w[chained single single_sampled].each do |mode|
      assert_raises(ArgumentError) { runner(client).run(base_input, mode: mode, passes: %w[security brief]) }
    end
  end

  def test_a_brief_that_is_not_an_object_is_an_error
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {"brief" => {"error" => "cut off"}})
    result = runner(client).run(base_input, passes: %w[brief])

    assert_equal "cut off", result.pass_results.first.error
    assert_nil result.pass_results.first.data
  end
end
