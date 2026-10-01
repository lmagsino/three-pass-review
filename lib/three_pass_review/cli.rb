# frozen_string_literal: true

require "optparse"

module ThreePassReview
  class CLI
    EXIT_OK = 0
    EXIT_ERROR = 1
    EXIT_FINDINGS = 2
    EXIT_REFUSED = 3

    USAGE = <<~TEXT
      Usage: threepass review --diff PATH|- [options]

      Reviews a unified diff with three independent passes and prints one reconciled comment.

      Exit codes: 0 ran, 1 error, 2 findings at or above --fail-on, 3 refused by the cost ceiling.
      Set THREEPASS_FAKE=DIR to replay fixture responses instead of calling the API.
    TEXT

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @env = env
    end

    def run(argv)
      argv = argv.dup
      return version if argv.intersect?(%w[--version -v])

      command = argv.shift
      return help(EXIT_OK) if command.nil? || %w[help --help -h].include?(command)
      return help(EXIT_ERROR, "unknown command: #{command}") unless command == "review"

      review(parse_review_options(argv))
    rescue OptionParser::ParseError, ArgumentError => e
      help(EXIT_ERROR, e.message)
    rescue Budget::Refused => e
      refused(e)
    rescue Error, SystemCallError => e
      @stderr.puts "threepass: #{e.message}"
      EXIT_ERROR
    end

    private

    def version
      @stdout.puts "threepass #{VERSION}"
      EXIT_OK
    end

    def help(code, problem = nil)
      @stderr.puts "threepass: #{problem}\n\n" if problem
      (code.zero? ? @stdout : @stderr).puts(USAGE, review_parser({}).summarize)
      code
    end

    def review_parser(opts)
      OptionParser.new do |o|
        o.banner = ""
        o.on("--diff PATH", "Unified diff to review, or - for stdin (required)") { |v| opts[:diff] = v }
        o.on("--title TEXT", "PR title") { |v| opts[:title] = v }
        o.on("--body-file PATH", "File holding the PR body") { |v| opts[:body_file] = v }
        o.on("--repo PATH", "Checkout of the head version (default .)") { |v| opts[:repo] = v }
        o.on("--config PATH", "Config file (default REPO/.threepass.yml if present)") { |v| opts[:config] = v }
        o.on("--format FORMAT", %w[markdown json], "markdown (default) or json") { |v| opts[:format] = v }
        o.on("--mode MODE", Runner::MODES, "independent (default); the others exist for the eval") { |v| opts[:mode] = v }
        o.on("--fail-on SEVERITY", Finding::SEVERITIES, "Exit 2 if any finding is at least this severe") { |v| opts[:fail_on] = v }
        o.on("--brief", "Add a reviewer brief for people: the change at a high level, risks, where to look first") { opts[:brief] = true }
        o.on("--no-cost-ceiling", "Run even without pricing; spend is not capped") { opts[:no_ceiling] = true }
      end
    end

    def parse_review_options(argv)
      opts = {repo: ".", format: "markdown", mode: "independent"}
      rest = review_parser(opts).parse(argv)
      raise ArgumentError, "unexpected arguments: #{rest.join(" ")}" if rest.any?
      raise ArgumentError, "--diff is required" unless opts[:diff]
      raise ArgumentError, "--repo #{opts[:repo]} is not a directory" unless File.directory?(opts[:repo])

      opts
    end

    def review(opts)
      @format = opts[:format]
      config = Config.load(opts[:config] || default_config(opts[:repo]))
      diff_text = (opts[:diff] == "-") ? @stdin.read : File.read(opts[:diff])
      body = opts[:body_file] ? File.read(opts[:body_file]) : nil
      outcome = Review.new(config: config, client: client, repo: opts[:repo], enforce_ceiling: !opts[:no_ceiling])
        .run(diff_text: diff_text, title: opts[:title], body: body, mode: opts[:mode], brief: opts[:brief])

      formatter = (@format == "json") ? Formatters::JSON : Formatters::Markdown
      @stdout.write(formatter.new(outcome).render)
      exit_code(outcome, opts[:fail_on])
    end

    def default_config(repo)
      path = File.join(repo, Config::FILE_NAME)
      File.file?(path) ? path : nil
    end

    def client
      fake = @env["THREEPASS_FAKE"]
      return LLM::FakeClient.new(fake) if fake && !fake.empty?

      LLM::AnthropicClient.new(api_key: @env["ANTHROPIC_API_KEY"])
    end

    def exit_code(outcome, fail_on)
      results = outcome.result.pass_results
      if results.any? && results.none?(&:ok?)
        @stderr.puts "threepass: every pass failed: #{results.map(&:error).uniq.join("; ")}"
        return EXIT_ERROR
      end
      limit = fail_on && Finding::SEVERITIES.index(fail_on)
      return EXIT_FINDINGS if limit && outcome.reconciled.findings.any? { |f| f.severity_rank <= limit }

      EXIT_OK
    end

    def refused(error)
      @stderr.puts "threepass: refused: #{error.message}"
      if @format == "json"
        @stdout.write("#{::JSON.pretty_generate("refused" => true, "reason" => error.message,
          "degradations" => error.degradations, "estimated_usd" => error.estimate&.total_usd)}\n")
      else
        @stdout.write("#{Formatters::Markdown::MARKER}\n\n### threepass: not run\n\n" \
          "#{Formatters::Text.block(error.message)}\n")
      end
      EXIT_REFUSED
    end
  end
end
