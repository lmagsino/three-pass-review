# frozen_string_literal: true

require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: %i[test standard]

desc "Manual smoke run: one real review of a fixture diff, under the default cost ceiling. Needs ANTHROPIC_API_KEY. Never run in CI."
task :smoke do
  require_relative "lib/three_pass_review"
  tpr = ThreePassReview

  outcome = tpr::Review.new(config: tpr::Config.new, client: tpr::LLM::AnthropicClient.new, repo: "test/fixtures/repo")
    .run(diff_text: File.read("test/fixtures/diffs/basic.patch"), title: "Add sortable invoices",
      body: "Lets users sort invoices by column.")
  outcome.result.pass_results.each do |r|
    puts "#{r.pass}: #{r.error || "#{r.findings.size} findings"} (#{r.input_tokens} input / #{r.output_tokens} output tokens)"
    r.findings.each { |f| puts "  - #{f["severity"]} #{f["file"]}:#{f["line_start"]} #{f["title"]} (#{f["confidence"]})" }
  end
  puts format("estimated $%.4f, actual $%.4f", outcome.plan.estimate.total_usd, outcome.accounting.total_usd)
end

namespace :eval do
  cases_dir = "evals/cases"

  load_cases = lambda do
    require_relative "lib/three_pass_review/eval"
    cases = ThreePassReview::Eval::Dataset.load(cases_dir)
    cases.each do |c|
      puts "#{c.valid? ? "ok  " : "FAIL"} #{c.id}"
      c.problems.each { |p| puts "       #{p}" }
    end
    abort "eval: no cases in #{cases_dir}" if cases.empty?
    abort "eval: #{cases.count { |c| !c.valid? }} invalid case(s)" unless cases.all?(&:valid?)
    cases
  end

  git_sha = lambda do
    sha = `git rev-parse --short HEAD 2>/dev/null`.strip
    dirty = `git status --porcelain 2>/dev/null`.strip.empty? ? "" : "-dirty"
    sha.empty? ? "unknown" : "#{sha}#{dirty}"
  end

  desc "Validate every case in evals/cases"
  task :validate do
    cases = load_cases.call
    kinds = cases.group_by(&:kind).transform_values(&:size)
    puts "#{cases.size} cases (#{kinds.map { |k, v| "#{v} #{k}" }.join(", ")}), dataset version " \
      "#{ThreePassReview::Eval::Dataset.version(cases_dir)}"
  end

  desc "Run a config over the dataset. Needs ANTHROPIC_API_KEY and CONFIRM=yes. EVAL_FAKE=DIR replays fixtures instead."
  task :run, [:config] do |_, args|
    tpr = ThreePassReview
    name = args[:config] || "independent"
    config_path = "evals/configs/#{name}.yml"
    abort "eval: no config #{config_path}" unless File.file?(config_path)
    cases = load_cases.call
    eval_config = YAML.safe_load_file(config_path)
    fake = ENV["EVAL_FAKE"].to_s
    if fake.empty?
      runs = eval_config.fetch("runs", 3)
      ceiling = tpr::Config.new(eval_config["threepass"] || {}).max_cost_usd
      bound = cases.size * runs * ceiling
      unless ENV["CONFIRM"] == "yes"
        abort format("eval: this reviews %d cases %d times each with the real API and can spend up to $%.2f " \
          "(%d reviews x max_cost_usd $%.2f). Re-run with CONFIRM=yes to go ahead.", cases.size, runs, bound, cases.size * runs, ceiling)
      end
      client = tpr::LLM::AnthropicClient.new
      factory = ->(_kase) { client }
      kind = "anthropic"
      results_root = "evals/results"
      labels_dir = "evals/labels"
    else
      factory = ->(kase) { tpr::LLM::FakeClient.new(File.join(fake, kase.id)) }
      kind = "fake"
      results_root = "tmp/eval-fake/results"
      labels_dir = "tmp/eval-fake/labels"
    end
    dir = tpr::Eval::Runner.new(cases: cases, config_name: name, eval_config: eval_config, client_factory: factory,
      client_kind: kind, results_root: results_root, labels_dir: labels_dir,
      dataset_version: tpr::Eval::Dataset.version(cases_dir), git_sha: git_sha.call).run
    puts "Results: #{dir}"
    puts "Label the unmatched findings in #{labels_dir}/#{File.basename(dir)}.yml, then run rake eval:report."
  end
end
