# frozen_string_literal: true

require "test_helper"

class AnthropicClientTest < Minitest::Test
  Block = Struct.new(:type, :text)
  Usage = Struct.new(:input_tokens, :output_tokens)
  Message = Struct.new(:content, :usage, :stop_reason, :stop_details)
  Count = Struct.new(:input_tokens)

  class FakeMessages
    attr_reader :created, :counted

    def initialize(message)
      @message = message
    end

    def create(**params)
      @created = params
      @message
    end

    def count_tokens(**params)
      @counted = params
      Count.new(input_tokens: 1234)
    end
  end

  FakeSDK = Struct.new(:messages)

  def client_for(message)
    messages = FakeMessages.new(message)
    [ThreePassReview::LLM::AnthropicClient.new(sdk: FakeSDK.new(messages)), messages]
  end

  def request(effort: "medium")
    ThreePassReview::LLM::Request.new(pass: "security", model: "claude-sonnet-5-5", system: "SYS", user: "USER",
      max_tokens: 4000, effort: effort, schema: ThreePassReview::Finding.schema(%w[security]))
  end

  def api_message(text, stop: :end_turn)
    Message.new(content: [Block.new(type: :thinking, text: nil), Block.new(type: :text, text: text)],
      usage: Usage.new(input_tokens: 1500, output_tokens: 300), stop_reason: stop)
  end

  def test_sends_structured_output_request_without_tools
    client, messages = client_for(api_message('{"findings":[]}'))
    client.complete(request)
    params = messages.created

    assert_equal "claude-sonnet-5-5", params[:model]
    assert_equal 4000, params[:max_tokens]
    assert_equal [{type: "text", text: "SYS"}], params[:system_]
    assert_equal [{role: "user", content: "USER"}], params[:messages]
    assert_equal :json_schema, params[:output_config][:format][:type]
    assert_equal :medium, params[:output_config][:effort]
    refute params.key?(:tools)
    refute params.key?(:tool_choice)
  end

  def test_omits_effort_when_not_configured
    client, messages = client_for(api_message('{"findings":[]}'))
    client.complete(request(effort: nil))

    refute messages.created[:output_config].key?(:effort)
  end

  def test_parses_findings_and_usage
    client, = client_for(api_message('{"findings":[{"title":"x"}]}'))
    response = client.complete(request)

    assert_equal [{"title" => "x"}], response.data["findings"]
    assert_equal [1500, 300, "end_turn", nil],
      [response.input_tokens, response.output_tokens, response.stop_reason, response.error]
  end

  def test_truncated_output_keeps_usage_and_reports_an_error
    client, = client_for(api_message('{"findings":[{"tit', stop: :max_tokens))
    response = client.complete(request)

    assert_nil response.data
    assert_match(/cut off at max_output_tokens/, response.error)
    assert_equal 300, response.output_tokens
  end

  def test_refusal_is_an_error
    refused = api_message("", stop: :refusal)
    refused.stop_details = Struct.new(:category).new(:cyber)
    client, = client_for(refused)

    assert_match(/declined to review \(cyber\)/, client.complete(request).error)
  end

  def test_invalid_json_is_an_error
    client, = client_for(api_message("not json"))

    assert_equal "reply was not valid JSON", client.complete(request).error
  end

  def test_count_tokens_sends_the_same_prompt_without_max_tokens
    client, messages = client_for(api_message("{}"))

    assert_equal 1234, client.count_tokens(request)
    assert_equal "SYS", messages.counted[:system_].first[:text]
    refute messages.counted.key?(:max_tokens)
  end

  def test_missing_api_key_is_refused
    assert_raises(ThreePassReview::Error) { ThreePassReview::LLM::AnthropicClient.new(api_key: nil) }
  end
end
