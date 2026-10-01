# frozen_string_literal: true

require "test_helper"
require "three_pass_review/eval"
require "tmpdir"
require "fileutils"

module EvalSupport
  EVAL = File.join(FIXTURES, "eval")
  CASES = File.join(EVAL, "cases")

  def eval_cases
    ThreePassReview::Eval::Dataset.load(CASES)
  end

  def defect(id: "d1", file: "app/models/invoice.rb", lines: [8, 8], category: "security")
    ThreePassReview::Eval::Defect.new(id: id, file: file, line_start: lines[0], line_end: lines[1], category: category,
      subcategory: "x", severity: "high", description: "d")
  end

  def eval_finding(file: "app/models/invoice.rb", lines: [8, 8], category: "security", title: "T")
    {"file" => file, "line_start" => lines[0], "line_end" => lines[1], "category" => category, "title" => title}
  end

  def eval_run(dir, config: "independent", today: Date.new(2026, 10, 1), cases: eval_cases, kind: "fake")
    eval_config = {"mode" => config, "runs" => 3, "model_training_cutoff" => "2026-06", "threepass" => {}}
    ThreePassReview::Eval::Runner.new(
      cases: cases, config_name: config, eval_config: eval_config,
      client_factory: ->(kase) { ThreePassReview::LLM::FakeClient.new(File.join(EVAL, "fake", kase.id)) },
      client_kind: kind, results_root: File.join(dir, "results"), labels_dir: File.join(dir, "labels"),
      dataset_version: "testversion", git_sha: "abc1234", today: today
    ).run(io: StringIO.new)
  end
end
Minitest::Test.include(EvalSupport)
