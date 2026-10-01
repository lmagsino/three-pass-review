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
