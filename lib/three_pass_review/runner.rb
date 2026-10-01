# frozen_string_literal: true

module ThreePassReview
  # data holds the brief's parsed reply; checks report findings instead.
  PassResult = Data.define(:pass, :sample, :findings, :input_tokens, :output_tokens, :stop_reason, :error, :data) do
    def initialize(data: nil, **rest)
      super
    end

    def ok?
      error.nil?
    end
  end

  RunResult = Data.define(:mode, :model, :pass_results)

  # Runs the passes for one review. `independent` is the product; `chained`,
  # `single` and `single_sampled` exist only so the eval can compare against it.
  class Runner
    MODES = %w[independent chained single single_sampled].freeze
    PASS_ORDER = %w[correctness security architecture].freeze
    BRIEF = "brief"

    attr_reader :model, :max_output_tokens, :samples

    def initialize(client:, model:, max_output_tokens: 4000, effort: nil, samples: 3)
      @client = client
      @model = model
      @max_output_tokens = max_output_tokens
      @effort = effort
      @samples = samples
    end

    # Requests whose content is known before any call: everything except the
    # earlier findings that chained mode adds.
    def planned_requests(input, mode:, passes: PASS_ORDER)
      validate!(input, mode, passes)
      case mode
      when "independent"
        keys = ordered(passes) + (passes.include?(BRIEF) ? [BRIEF] : [])
        keys.map { |key| [request(key, input), 1] }
      when "chained" then ordered(passes).map { |key| [request(key, input), 1] }
      when "single" then [[request("combined", input), 1]]
      when "single_sampled" then (1..samples).map { |n| [request("combined", input), n] }
      end
    end

    # guard: optional callable(request, results_so_far) -> reason or nil, checked
    # before each chained call. Independent calls are all covered by the
    # estimate made before the run.
    def run(input, mode: "independent", passes: PASS_ORDER, guard: nil)
      planned = planned_requests(input, mode: mode, passes: passes)
      results = (mode == "chained") ? run_chained(input, passes, guard) : run_parallel(planned)
      RunResult.new(mode: mode, model: model, pass_results: results.freeze)
    end

    private

    def validate!(input, mode, passes)
      raise ArgumentError, "unknown mode #{mode}" unless MODES.include?(mode)
      raise ArgumentError, "the brief runs only in independent mode" if passes.include?(BRIEF) && mode != "independent"
      raise ArgumentError, "the base input must be deep-frozen" unless ThreePassReview.deep_frozen?(input)
    end

    def ordered(passes)
      PASS_ORDER.select { |key| passes.include?(key) }
    end

    def request(key, input, prior: {})
      Passes.fetch(key).build_request(input, model: model, max_tokens: max_output_tokens, effort: @effort, prior: prior)
    end

    # Every request is built before any thread starts, from the frozen base
    # input, so no pass can see what another one returns.
    def run_parallel(planned)
      planned.map { |req, sample| Thread.new { call(req, sample) } }.map(&:value)
    end

    def run_chained(input, passes, guard)
      prior = {}
      ordered(passes).each_with_object([]) do |key, results|
        req = request(key, input, prior: prior.dup)
        reason = guard&.call(req, results)
        result = reason ? skipped(req, reason) : call(req, 1)
        prior[key] = result.findings unless reason
        results << result
      end
    end

    def skipped(request, reason)
      PassResult.new(pass: request.pass, sample: 1, findings: [].freeze, input_tokens: 0, output_tokens: 0,
        stop_reason: nil, error: reason.dup.freeze)
    end

    def call(request, sample)
      response = @client.complete(request)
      data = response.data.is_a?(Hash) ? response.data : nil
      brief = request.pass == BRIEF
      findings = brief ? [] : data&.dig("findings")
      error = response.error ||
        if brief
          data ? nil : "reply was not an object"
        else
          findings.is_a?(Array) ? nil : "reply had no findings list"
        end
      ThreePassReview.deep_freeze(PassResult.new(
        pass: request.pass, sample: sample, findings: error ? [] : findings,
        input_tokens: response.input_tokens, output_tokens: response.output_tokens,
        stop_reason: response.stop_reason, error: error, data: (brief && !error) ? data : nil
      ))
    rescue => e
      PassResult.new(pass: request.pass, sample: sample, findings: [].freeze, input_tokens: 0, output_tokens: 0,
        stop_reason: nil, error: "#{e.class}: #{e.message}".freeze)
    end
  end
end
