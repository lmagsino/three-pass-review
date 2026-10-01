# frozen_string_literal: true

require "json"

module ThreePassReview
  module LLM
    # Calls the Messages API through the official anthropic gem.
    #
    # Findings come back through structured outputs (output_config.format), not
    # a forced report_findings tool call: claude-sonnet-5-5 rejects a forced
    # tool_choice with a 400, and structured outputs is Anthropic's documented
    # replacement when the forced call only existed to get JSON back.
    class AnthropicClient < Client
      def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY", nil), sdk: nil, max_retries: 2, timeout: 300)
        super()
        @sdk = sdk || begin
          require "anthropic"
          raise Error, "ANTHROPIC_API_KEY is not set" if api_key.to_s.empty?

          Anthropic::Client.new(api_key: api_key, max_retries: max_retries, timeout: timeout)
        end
      end

      def complete(request)
        # No automatic retries: a retried call can be billed twice while the
        # budget counted it once. count_tokens is free, so it keeps them.
        message = @sdk.messages.create(**params(request), max_tokens: request.max_tokens,
          request_options: {max_retries: 0})
        usage = message.usage
        stop = message.stop_reason&.to_sym
        text = message.content.select { |block| block.type.to_sym == :text }.map(&:text).join
        data = nil
        error =
          case stop
          when :refusal then "the model declined to review (#{refusal_category(message)})"
          when :max_tokens then "output cut off at max_output_tokens (#{request.max_tokens}); raise it"
          end
        unless error
          begin
            data = JSON.parse(text)
          rescue JSON::ParserError
            error = "reply was not valid JSON"
          end
        end
        Response.new(data: data, input_tokens: usage.input_tokens.to_i, output_tokens: usage.output_tokens.to_i,
          stop_reason: stop&.to_s, error: error)
      end

      def count_tokens(request)
        @sdk.messages.count_tokens(**params(request)).input_tokens
      end

      private

      def params(request)
        output_config = {format: {type: :json_schema, schema: request.schema}}
        output_config[:effort] = request.effort.to_sym if request.effort
        {
          model: request.model,
          system_: [{type: "text", text: request.system}],
          messages: [{role: "user", content: request.user}],
          output_config: output_config
        }
      end

      def refusal_category(message)
        details = message.respond_to?(:stop_details) ? message.stop_details : nil
        details&.category || "no category given"
      end
    end
  end
end
