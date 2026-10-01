# frozen_string_literal: true

require_relative "eval_helper"

class EvalCaseTest < Minitest::Test
  def with_case(name)
    Dir.mktmpdir do |dir|
      target = File.join(dir, name)
      FileUtils.cp_r(File.join(CASES, name), target)
      yield target
    end
  end

  def edit(dir)
    path = File.join(dir, "case.yml")
    data = YAML.safe_load_file(path, permitted_classes: [Date])
    yield data
    File.write(path, YAML.dump(data))
    ThreePassReview::Eval::Case.load(dir)
  end

  def test_fixture_cases_are_valid
    eval_cases.each { |c| assert c.valid?, "#{c.id}: #{c.problems.join("; ")}" }
    assert_equal %w[t-clean t-planted t-real], eval_cases.map(&:id)
  end

  def test_reads_defects_and_metadata
    kase = eval_cases.find { |c| c.id == "t-real" }

    assert_equal [8, 8, "security"], [kase.defects.first.line_start, kase.defects.first.line_end, kase.defects.first.category]
    assert_equal Date.new(2026, 8, 1), kase.merged_at
    assert_equal "Add sortable invoices", kase.title
  end

  def test_rejects_non_permissive_licenses
    with_case("t-real") do |dir|
      kase = edit(dir) { |d| d["source"]["license"] = "GPL-3.0-only" }
      assert(kase.problems.any? { |p| p.include?("not permissive") })
    end
  end

  def test_rejects_defects_outside_changed_hunks
    with_case("t-real") do |dir|
      kase = edit(dir) { |d| d["defects"][0]["lines"] = [40, 41] }
      assert_includes kase.problems, "defect d1: lines 40-41 are not inside a changed hunk"
    end
  end

  def test_rejects_defects_in_files_not_in_the_diff
    with_case("t-real") do |dir|
      kase = edit(dir) { |d| d["defects"][0]["file"] = "app/models/user.rb" }
      assert_includes kase.problems, "defect d1: app/models/user.rb is not in the diff"
    end
  end

  def test_kind_rules
    with_case("t-real") do |dir|
      assert_includes edit(dir) { |d| d["source"].delete("fixed_by") }.problems, "source.fixed_by is required for real cases"
      assert_includes edit(dir) { |d| d["kind"] = "clean" }.problems, "clean cases have no defects"
      assert_includes edit(dir) { |d| d["kind"] = "planted" }.problems, "notes must say how the bug was planted"
      assert_includes edit(dir) { |d| d["id"] = "other" }.problems, "id \"other\" doesn't match the directory name"
    end
  end

  def test_context_must_match_the_diff
    with_case("t-real") do |dir|
      File.write(File.join(dir, "context/app/models/invoice.rb"), "class Invoice\nend\n")
      kase = ThreePassReview::Eval::Case.load(dir)
      assert(kase.problems.any? { |p| p.start_with?("context/app/models/invoice.rb doesn't match the diff") })

      FileUtils.rm(File.join(dir, "context/app/models/invoice.rb"))
      assert_includes ThreePassReview::Eval::Case.load(dir).problems, "context/app/models/invoice.rb is missing"
    end
  end

  def test_missing_or_broken_files
    Dir.mktmpdir do |dir|
      empty = File.join(dir, "empty")
      FileUtils.mkdir_p(empty)
      assert_equal ["case.yml is missing"], ThreePassReview::Eval::Case.load(empty).problems
    end
    with_case("t-real") do |dir|
      File.write(File.join(dir, "diff.patch"), "@@ -1 +1 @@\n")
      assert(ThreePassReview::Eval::Case.load(dir).problems.any? { |p| p.start_with?("diff.patch doesn't parse") })
    end
  end

  def test_dataset_version_tracks_every_file
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir[File.join(CASES, "*")], dir)
      before = ThreePassReview::Eval::Dataset.version(dir)
      assert_equal before, ThreePassReview::Eval::Dataset.version(dir)

      File.write(File.join(dir, "t-clean/context/lib/plain.rb"), "changed\n")
      after_edit = ThreePassReview::Eval::Dataset.version(dir)
      refute_equal before, after_edit

      FileUtils.mkdir_p(File.join(dir, "t-clean/context/.github"))
      File.write(File.join(dir, "t-clean/context/.github/copilot-instructions.md"), "rules\n")
      refute_equal after_edit, ThreePassReview::Eval::Dataset.version(dir)
    end
  end
end
