# frozen_string_literal: true

require_relative "eval_helper"

class EvalHarnessTest < Minitest::Test
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

  def test_run_writes_records_summary_misses_and_labels
    assert_equal "2026-10-01-independent-claude-sonnet-5-5", File.basename(@run_dir)
    %w[records.json summary.json summary.md misses.md].each { |f| assert File.file?(File.join(@run_dir, f)), f }
    records = JSON.parse(File.read(File.join(@run_dir, "records.json")))

    assert_equal 9, records["records"].size # 3 cases x 3 runs
    assert_equal "fake", records.dig("meta", "client")
    %w[model sampling prompts dataset_version git_sha threepass_config date].each { |k| assert records["meta"].key?(k), k }
  end

  def test_recall_is_scored_per_defect_by_majority
    recall = summary.dig("metrics", "recall")

    assert_equal({"k" => 2, "n" => 2}, recall["strict"].slice("k", "n"))
    assert_equal({"min" => 1.0, "max" => 1.0}, recall["stability"].slice("min", "max"))
    assert_equal "1 of 1", recall.dig("by_category", "security", "text")
    assert_equal({"after" => "1 of 1", "before" => "1 of 1"}, recall["by_cutoff"].transform_values { |v| v["text"] })
  end

  def test_unmatched_findings_go_to_the_labels_file
    labels = YAML.safe_load_file(Dir[File.join(@dir, "labels", "*.yml")].first)["findings"]

    assert(labels.all? { |l| l["label"] == "unlabeled" })
    assert(labels.any? { |l| l["case"] == "t-clean" && l["file"] == "lib/plain.rb" })
    assert(labels.any? { |l| l["from"].include?("pass:architecture") })
  end

  def test_precision_is_refused_while_labels_are_missing
    precision = summary.dig("metrics", "precision")

    assert_nil precision["value"]
    assert_nil precision["false_positives_per_clean_pr"]
    assert_operator precision["unlabeled_share"], :>, 0.05
    assert_includes File.read(File.join(@run_dir, "summary.md")), "unverified:"
  end

  def test_every_config_runs
    %w[chained single single_sampled].each do |config|
      dir = eval_run(@dir, config: config)
      assert File.file?(File.join(dir, "summary.json")), config
    end
  end

  def test_threshold_sweep_covers_point_three_to_point_nine
    sweep = summary.dig("metrics", "threshold_sweep")

    assert_equal %w[0.3 0.4 0.5 0.6 0.7 0.8 0.9], sweep.keys
    assert_operator sweep["0.3"]["recall"]["k"], :>=, sweep["0.9"]["recall"]["k"]
  end

  def test_a_failing_review_is_recorded_and_the_run_carries_on
    broken = eval_cases.map(&:dup)
    Dir.mktmpdir do |dir|
      eval_config = {"mode" => "independent", "runs" => 1, "threepass" => {}}
      factory = lambda do |kase|
        raise IOError, "rate limited" if kase.id == "t-planted"

        ThreePassReview::LLM::FakeClient.new(File.join(EVAL, "fake", kase.id))
      end
      run_dir = ThreePassReview::Eval::Runner.new(cases: broken, config_name: "independent", eval_config: eval_config,
        client_factory: factory, client_kind: "fake", results_root: dir, labels_dir: File.join(dir, "labels"),
        dataset_version: "v", git_sha: "x").run(io: StringIO.new)
      records = JSON.parse(File.read(File.join(run_dir, "records.json")))["records"]

      assert_equal %w[t-clean t-planted t-real], records.map { |r| r["case"] }
      assert_equal "IOError: rate limited", records[1]["error"]
      assert_equal "0 of 1", JSON.parse(File.read(File.join(run_dir, "summary.json"))).dig("metrics", "recall", "by_category", "correctness", "text")
    end
  end

  def test_records_naming_unknown_cases_are_a_clear_error
    error = assert_raises(ThreePassReview::Error) do
      ThreePassReview::Eval::Scorer.new(cases: eval_cases.first(1), records: [{"case" => "gone"}], labels: nil, runs: 3)
    end
    assert_match(/aren't in the dataset: gone/, error.message)
  end

  def test_sweep_only_findings_are_in_the_labels_file
    entries = YAML.safe_load_file(Dir[File.join(@dir, "labels", "*.yml")].first)["findings"]

    assert(entries.any? { |e| e["from"].include?("sweep") })
  end

  def test_same_day_runs_get_distinct_ids
    second = eval_run(@dir)

    assert_equal "#{@run_dir}-2", second
  end
end
