# frozen_string_literal: true

require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: %i[test standard]

desc "Manual smoke run: three real API calls on a fixture diff. Needs ANTHROPIC_API_KEY. Never run in CI."
task :smoke do
  require_relative "lib/three_pass_review"
  tpr = ThreePassReview

  diff = tpr::Diff.parse(File.read("test/fixtures/diffs/basic.patch"))
  input = tpr::ContextBuilder.new(repo: "test/fixtures/repo")
    .build(diff: diff, title: "Add sortable invoices", body: "Lets users sort invoices by column.")
  runner = tpr::Runner.new(client: tpr::LLM::AnthropicClient.new, model: ENV.fetch("THREEPASS_MODEL", "claude-sonnet-5-5"),
    max_output_tokens: 4000, effort: "medium")
  runner.run(input).pass_results.each do |r|
    puts "#{r.pass}: #{r.error || "#{r.findings.size} findings"} (#{r.input_tokens} input / #{r.output_tokens} output tokens)"
    r.findings.each { |f| puts "  - #{f["severity"]} #{f["file"]}:#{f["line_start"]} #{f["title"]} (#{f["confidence"]})" }
  end
end
