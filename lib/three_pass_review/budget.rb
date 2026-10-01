# frozen_string_literal: true

module ThreePassReview
  # Enforces max_cost_usd: estimate before calling, degrade in a fixed order,
  # refuse rather than exceed, and account for what the calls actually cost.
  class Budget
    CHARS_PER_TOKEN = 3.5

    CallCost = Data.define(:pass, :sample, :input_tokens, :output_tokens, :cost_usd, :counted_by)
    Estimate = Data.define(:calls, :total_usd)
    Accounting = Data.define(:calls, :total_usd, :input_tokens, :output_tokens)
    Plan = Data.define(:input, :passes, :estimate, :degradations)

    class Refused < Error
      attr_reader :estimate, :degradations

      def initialize(message, estimate: nil, degradations: [])
        super(message)
        @estimate = estimate
        @degradations = degradations
      end
    end

    attr_reader :max_cost_usd

    # pricing: {input:, output:} in USD per million tokens, or nil if unknown.
    # enforce: false is --no-cost-ceiling; costs are still reported when known.
    def initialize(client:, max_cost_usd:, pricing:, enforce: true)
      if enforce && pricing.nil?
        raise Refused, "no pricing configured for this model, so the cost ceiling can't be enforced. " \
          "Add it under pricing: in .threepass.yml, or pass --no-cost-ceiling"
      end

      @client = client
      @max_cost_usd = max_cost_usd
      @pricing = pricing
      @enforce = enforce
      @counts = {}
      @mutex = Mutex.new
    end

    def cost(input_tokens, output_tokens)
      return nil unless @pricing

      (input_tokens * @pricing[:input] + output_tokens * @pricing[:output]) / 1_000_000.0
    end

    # Tries each step in order and returns the first plan under the ceiling:
    # full context, smaller excerpts, diff only, diff only without the
    # architecture pass. Raises Refused when none fits.
    def plan(builder:, diff:, title:, body:, runner:, mode:, passes:, lines_around_hunk:, reduced_lines_around_hunk:)
      steps = [[nil, lines_around_hunk, passes]]
      steps << ["smaller_excerpts", reduced_lines_around_hunk, passes] if reduced_lines_around_hunk < lines_around_hunk
      steps << ["diff_only", nil, passes]
      if %w[independent chained].include?(mode) && passes.include?("architecture") && passes.size > 1
        steps << ["skipped_architecture", nil, passes - ["architecture"]]
      end

      degradations = []
      estimate = nil
      steps.each do |degradation, lines, pass_list|
        degradations << degradation if degradation
        input = builder.build(diff: diff, title: title, body: body, lines_around_hunk: lines)
        estimate = estimate(runner, input, mode: mode, passes: pass_list)
        if !@enforce || estimate.total_usd <= max_cost_usd
          return Plan.new(input: input, passes: pass_list, estimate: estimate, degradations: degradations.dup)
        end
      end
      raise Refused.new(
        format("estimated cost $%.4f is over max_cost_usd $%.2f even after %s", estimate.total_usd, max_cost_usd,
          degradations.join(", ")),
        estimate: estimate, degradations: degradations
      )
    end

    # Output is priced at max_tokens, the most a call can be billed for. In
    # chained mode each later pass is also sent the earlier passes' findings,
    # which can't be longer than their max_tokens of output.
    def estimate(runner, input, mode:, passes:)
      calls = runner.planned_requests(input, mode: mode, passes: passes).each_with_index.map do |(request, sample), i|
        input_tokens, counted_by = input_tokens(request)
        input_tokens += i * request.max_tokens if mode == "chained"
        CallCost.new(pass: request.pass, sample: sample, input_tokens: input_tokens, output_tokens: request.max_tokens,
          cost_usd: cost(input_tokens, request.max_tokens), counted_by: counted_by)
      end
      Estimate.new(calls: calls, total_usd: sum(calls))
    end

    # Checked before each chained call, whose input isn't known up front.
    # Returns a reason to skip the call, or nil to make it.
    def guard
      return nil unless @enforce

      lambda do |request, results_so_far|
        spent = account_results(results_so_far).total_usd
        next_call = cost(input_tokens(request).first, request.max_tokens)
        (spent + next_call > max_cost_usd) ? "skipped: would go over max_cost_usd" : nil
      end
    end

    def account(result)
      account_results(result.pass_results)
    end

    private

    def account_results(results)
      calls = results.map do |r|
        CallCost.new(pass: r.pass, sample: r.sample, input_tokens: r.input_tokens, output_tokens: r.output_tokens,
          cost_usd: cost(r.input_tokens, r.output_tokens), counted_by: :usage)
      end
      Accounting.new(calls: calls, total_usd: sum(calls), input_tokens: calls.sum(&:input_tokens),
        output_tokens: calls.sum(&:output_tokens))
    end

    def sum(calls)
      return nil if calls.any? { |c| c.cost_usd.nil? }

      calls.sum(0.0, &:cost_usd)
    end

    # Uses the provider's token counter when it has one; otherwise characters
    # divided by CHARS_PER_TOKEN. Identical requests are counted once.
    def input_tokens(request)
      @mutex.synchronize do
        @counts[request] ||= begin
          counted = @client.count_tokens(request)
          counted ? [counted, :count_tokens] : [(request.chars / CHARS_PER_TOKEN).ceil, :chars]
        end
      end
    end
  end
end
