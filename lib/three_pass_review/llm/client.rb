# frozen_string_literal: true

module ThreePassReview
  module LLM
    # A provider-neutral request: one system prompt, one user message, and the
    # JSON schema the reply must follow. The model gets no tools.
    Request = Data.define(:pass, :model, :system, :user, :max_tokens, :effort, :schema) do
      def chars
        system.size + user.size + JSON.generate(schema).size
      end
    end

    # data is the parsed JSON reply, or nil when error is set. Token usage is
    # reported even when the reply is unusable, because it was still billed.
    Response = Data.define(:data, :input_tokens, :output_tokens, :stop_reason, :error)

    class Client
      def complete(_request)
        raise NotImplementedError
      end

      # Input tokens the request would use, or nil if the provider can't count.
      def count_tokens(_request)
        nil
      end
    end
  end
end
