# frozen_string_literal: true

require "json"

module ThreePassReview
  module LLM
    # Replays fixture responses and records every request. Used by the tests,
    # by THREEPASS_FAKE runs of the CLI, and by eval runs without an API key.
    #
    # A fixture directory holds one JSON file per pass: <pass>-<call>.json is
    # used for that pass's nth call if present, otherwise <pass>.json. Each
    # file is {"findings": [...]}, optionally with "usage", "stop_reason" and
    # "error". Without "usage", tokens are estimated from the text sizes.
    class FakeClient < Client
      attr_reader :requests

      def initialize(fixture_dir = nil, responses: {}, token_count: nil, on_complete: nil)
        super()
        @fixture_dir = fixture_dir
        @responses = responses.transform_keys(&:to_s)
        @token_count = token_count
        @on_complete = on_complete
        @requests = []
        @calls = Hash.new(0)
        @mutex = Mutex.new
      end

      def complete(request)
        call = @mutex.synchronize do
          @requests << request
          @calls[request.pass] += 1
        end
        @on_complete&.call(request)
        fixture = fixture_for(request.pass, call)
        output = JSON.generate("findings" => fixture.fetch("findings", []))
        usage = fixture["usage"] || {}
        Response.new(
          data: fixture["error"] ? nil : JSON.parse(output),
          input_tokens: usage.fetch("input_tokens") { (request.chars / 3.5).ceil },
          output_tokens: usage.fetch("output_tokens") { (output.size / 3.5).ceil },
          stop_reason: fixture.fetch("stop_reason", "end_turn"),
          error: fixture["error"]
        )
      end

      def count_tokens(request)
        @token_count.respond_to?(:call) ? @token_count.call(request) : @token_count
      end

      private

      def fixture_for(pass, call)
        if @responses.key?(pass)
          response = @responses[pass]
          return response.is_a?(Array) ? response.fetch(call - 1) { response.last } : response
        end
        raise Error, "FakeClient has no response for pass #{pass}" unless @fixture_dir

        numbered = File.join(@fixture_dir, "#{pass}-#{call}.json")
        path = File.exist?(numbered) ? numbered : File.join(@fixture_dir, "#{pass}.json")
        raise Error, "FakeClient fixture missing: #{path}" unless File.exist?(path)

        JSON.parse(File.read(path))
      end
    end
  end
end
