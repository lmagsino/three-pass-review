# frozen_string_literal: true

require "json"
require "yaml"
require "date"
require "time"
require "fileutils"

module ThreePassReview
  module Eval
    # Runs one configuration over every case, `runs` times each, and writes
    # evals/results/<date>-<config>-<model>/: records.json (raw per-review
    # output), summary.json, summary.md and misses.md, plus a labels file
    # listing every unmatched finding.
    class Runner
      def initialize(cases:, config_name:, eval_config:, client_factory:, client_kind:, results_root:, labels_dir:,
        dataset_version:, git_sha:, today: Date.today)
        @cases = cases
        @config_name = config_name
        @eval_config = eval_config
        @client_factory = client_factory
        @client_kind = client_kind
        @results_root = results_root
        @labels_dir = labels_dir
        @dataset_version = dataset_version
        @git_sha = git_sha
        @today = today
        @config = Config.new(eval_config.fetch("threepass", {}) || {})
      end

      def runs = @eval_config.fetch("runs", 3)
      def mode = @eval_config.fetch("mode")

      def run(io: $stdout)
        run_id = unique_run_id
        dir = File.join(@results_root, run_id)
        FileUtils.mkdir_p(dir)
        meta = metadata(run_id)
        records = []
        # Written after every review, so a crash part-way keeps what was paid for.
        save = -> { File.write(File.join(dir, "records.json"), JSON.pretty_generate("meta" => meta, "records" => records)) }
        @cases.each do |kase|
          (1..runs).each do |n|
            record = review(kase, n)
            records << record
            save.call
            io.puts format("  %-28s run %d  %s", kase.id, n, status(record))
          end
        end
        labels = Labels.new(@labels_dir)
        scorer = Eval.scorer(@cases, records, labels, meta)
        labels.write(run_id, scorer.label_entries)
        Summary.write(dir, meta, scorer.score)
        dir
      end

      private

      def unique_run_id
        base = "#{@today.iso8601}-#{@config_name}-#{@config.model}"
        id = base
        n = 1
        id = "#{base}-#{n += 1}" while File.exist?(File.join(@results_root, id))
        id
      end

      def review(kase, run)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        outcome = Review.new(config: @config, client: @client_factory.call(kase), repo: kase.context_dir)
          .run(diff_text: kase.diff_text, title: kase.title, body: kase.body, mode: mode)
        {"case" => kase.id, "run" => run, "refused" => false, "output" => Formatters::JSON.new(outcome).to_h,
         "latency_s" => elapsed(started)}
      rescue Budget::Refused => e
        {"case" => kase.id, "run" => run, "refused" => true, "reason" => e.message, "output" => nil,
         "latency_s" => elapsed(started)}
      rescue => e
        {"case" => kase.id, "run" => run, "refused" => false, "error" => "#{e.class}: #{e.message}", "output" => nil,
         "latency_s" => elapsed(started)}
      end

      def status(record)
        return "refused" if record["refused"]
        return "error: #{record["error"]}" if record["error"]

        "$#{record.dig("output", "cost", "total_usd")&.round(4)}"
      end

      def elapsed(started)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
      end

      def metadata(run_id)
        {
          "run_id" => run_id, "config" => @config_name, "mode" => mode, "runs" => runs, "date" => @today.iso8601,
          "started_at" => Time.now.utc.iso8601(3),
          "client" => @client_kind, "model" => @config.model,
          "sampling" => {"effort" => @config.effort, "max_output_tokens" => @config.max_output_tokens},
          "threepass_config" => @config.data, "prompts" => Prompts.hashes, "prompts_version" => Prompts.version,
          "dataset_version" => @dataset_version, "git_sha" => @git_sha,
          "model_training_cutoff" => @eval_config["model_training_cutoff"]&.to_s
        }
      end
    end

    def self.scorer(cases, records, labels, meta)
      cutoff = parse_cutoff(meta["model_training_cutoff"])
      config = meta["threepass_config"] || {}
      Scorer.new(cases: cases, records: records, labels: labels, runs: meta["runs"], gap: config.fetch("merge_line_gap", 3),
        max_comments: config.fetch("max_comments", 10), training_cutoff: cutoff)
    end

    # "2026-06" means the end of June 2026; a full date is taken as given.
    def self.parse_cutoff(value)
      return nil if value.nil? || value.to_s.empty?

      match = value.to_s.match(/\A(\d{4})-(\d{2})\z/)
      match ? Date.new(match[1].to_i, match[2].to_i, -1) : Date.parse(value.to_s)
    end
  end
end
