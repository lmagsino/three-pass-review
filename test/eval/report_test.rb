# frozen_string_literal: true

require_relative "eval_helper"

class EvalReportTest < Minitest::Test
  README = <<~MD
    # Project

    <!-- eval:start -->
    pending
    <!-- eval:end -->

    After the table.
  MD

  def setup
    @dir = Dir.mktmpdir
    @run_dir = eval_run(@dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def summary
    JSON.parse(File.read(File.join(@run_dir, "summary.json")))
  end

  def report(readme: nil)
    out = StringIO.new
    ThreePassReview::Eval::Report.new(results_root: File.join(@dir, "results"), cases: eval_cases,
      labels_dir: File.join(@dir, "labels"), dataset_version: "testversion", readme_path: readme).run(io: out)
    out.string
  end

  def label_everything(as)
    path = Dir[File.join(@dir, "labels", "*.yml")].first
    File.write(path, File.read(path).gsub("label: unlabeled", "label: #{as}"))
  end

  def test_report_rescores_with_new_labels
    label_everything("false_positive")
    out = report
    precision = summary.dig("metrics", "precision")

    refute_nil precision["value"]
    assert_equal 1.0, precision.dig("false_positives_per_clean_pr", "value")
    assert_includes out, "2026-10-01-independent-claude-sonnet-5-5 (fake)"
  end

  def test_unclear_labels_leave_the_denominator
    label_everything("unclear")
    report
    precision = summary.dig("metrics", "precision")

    assert_equal precision["matched"], precision.dig("value", "n")
    assert_in_delta 1.0, precision.dig("value", "rate")
  end

  def test_fake_runs_never_reach_the_readme
    Dir.mktmpdir do |dir|
      readme = File.join(dir, "README.md")
      File.write(readme, README)
      out = report(readme: readme)

      assert_equal README, File.read(readme)
      assert_includes out, "README not updated"
    end
  end

  def test_real_runs_update_only_the_block_between_the_markers
    records = File.join(@run_dir, "records.json")
    File.write(records, File.read(records).sub('"client": "fake"', '"client": "anthropic"'))
    Dir.mktmpdir do |dir|
      readme = File.join(dir, "README.md")
      File.write(readme, README)
      report(readme: readme)
      text = File.read(readme)

      assert text.start_with?("# Project\n\n<!-- eval:start -->\n| | Recall (95% CI) |")
      assert text.end_with?("<!-- eval:end -->\n\nAfter the table.\n")
      assert_includes text, "| **Reconciled output** | 2 of 2 | unverified:"
      assert_includes text, "Dataset: 3 cases (1 real, 1 planted, 1 clean), version testversion"
    end
  end

  def test_runs_on_an_older_dataset_version_are_not_published
    records = File.join(@run_dir, "records.json")
    File.write(records, File.read(records).sub('"client": "fake"', '"client": "anthropic"').sub('"dataset_version": "testversion"', '"dataset_version": "old"'))
    Dir.mktmpdir do |dir|
      readme = File.join(dir, "README.md")
      File.write(readme, README)
      out = report(readme: readme)

      assert_equal README, File.read(readme)
      assert_includes out, "skipped, made on dataset old"
    end
  end

  def test_misses_file_is_not_overwritten_by_the_report
    misses = File.join(@run_dir, "misses.md")
    File.write(misses, "human notes\n")
    report

    assert_equal "human notes\n", File.read(misses)
  end

  def test_report_skips_stale_runs_without_rescoring_them
    records = File.join(@run_dir, "records.json")
    File.write(records, File.read(records).sub('"dataset_version": "testversion"', '"dataset_version": "old"'))
    before = File.read(File.join(@run_dir, "summary.json"))
    label_everything("false_positive")
    report

    assert_equal before, File.read(File.join(@run_dir, "summary.json"))
  end

  def test_the_latest_run_is_published_not_the_largest_run_id
    score = JSON.parse(File.read(File.join(@run_dir, "summary.json")))["metrics"]
    run = ->(id, at) { {"meta" => {"run_id" => id, "config" => "independent", "started_at" => at}, "score" => score} }
    report = ThreePassReview::Eval::Report.new(results_root: @dir, cases: eval_cases, labels_dir: @dir, dataset_version: "v")
    table = report.table([run.call("2026-10-01-independent-m-9", "2026-10-01T09:00:00.000Z"),
      run.call("2026-10-01-independent-m-10", "2026-10-01T10:00:00.000Z")])

    assert_includes table, "evals/results/2026-10-01-independent-m-10`"
  end
end
