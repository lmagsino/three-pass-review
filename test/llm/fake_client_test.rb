# frozen_string_literal: true

require "test_helper"

class FakeClientTest < Minitest::Test
  def request(pass = "security")
    ThreePassReview::LLM::Request.new(pass: pass, model: "m", system: "s", user: "u", max_tokens: 10, effort: nil, schema: {})
  end

  def test_replays_fixture_files_and_records_requests
    client = ThreePassReview::LLM::FakeClient.new(File.join(FIXTURES, "llm", "basic"))
    response = client.complete(request)

    assert_equal "sql_injection", response.data["findings"].first["subcategory"]
    assert_equal [request], client.requests
    assert_operator response.output_tokens, :>, 0
  end

  def test_numbered_fixtures_win_for_their_call
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {"combined" => [{"findings" => []}, {"findings" => [{"x" => 1}]}]})

    assert_empty client.complete(request("combined")).data["findings"]
    assert_equal 1, client.complete(request("combined")).data["findings"].size
  end

  def test_usage_and_errors_come_from_the_fixture
    client = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "security" => {"error" => "cut off", "stop_reason" => "max_tokens", "usage" => {"input_tokens" => 7, "output_tokens" => 9}}
    })
    response = client.complete(request)

    assert_nil response.data
    assert_equal ["cut off", 7, 9], [response.error, response.input_tokens, response.output_tokens]
  end

  def test_missing_fixture_is_an_error
    client = ThreePassReview::LLM::FakeClient.new(File.join(FIXTURES, "llm", "basic"))

    assert_raises(ThreePassReview::Error) { client.complete(request("nonexistent")) }
  end
end
