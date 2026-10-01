# frozen_string_literal: true

require_relative "eval_helper"

class LabelsTest < Minitest::Test
  L = ThreePassReview::Eval::Labels

  def test_key_ignores_title_case_and_spacing_but_not_lines
    a = L.key("c1", eval_finding(title: "Nil  customer"))

    assert_equal a, L.key("c1", eval_finding(title: "nil customer"))
    refute_equal a, L.key("c1", eval_finding(title: "nil customer", lines: [9, 9]))
    refute_equal a, L.key("c2", eval_finding(title: "nil customer"))
  end

  def test_labels_carry_over_to_later_runs
    Dir.mktmpdir do |dir|
      key = L.key("c1", eval_finding)
      entry = {"key" => key, "case" => "c1", "file" => "f", "lines" => [8, 8], "title" => "T", "from" => ["reconciled"]}
      path = L.new(dir).write("run-1", [entry])
      assert_equal "unlabeled", YAML.safe_load_file(path)["findings"].first["label"]

      File.write(path, File.read(path).sub("label: unlabeled", "label: false_positive"))
      later = L.new(dir).write("run-2", [entry])

      assert_equal "false_positive", L.new(dir).label(key)
      assert_equal "false_positive", YAML.safe_load_file(later)["findings"].first["label"]
    end
  end

  def test_conflicting_labels_are_an_error_not_a_coin_toss
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.yml"), YAML.dump("findings" => [{"key" => "k", "label" => "real"}]))
      File.write(File.join(dir, "b.yml"), YAML.dump("findings" => [{"key" => "k", "label" => "false_positive"}]))

      error = assert_raises(ThreePassReview::Error) { L.new(dir) }
      assert_match(/make them agree/, error.message)
    end
  end

  def test_unknown_labels_are_refused
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "x.yml"), YAML.dump("findings" => [{"key" => "k", "label" => "wrong"}]))
      assert_raises(ThreePassReview::Error) { L.new(dir) }
    end
  end
end
