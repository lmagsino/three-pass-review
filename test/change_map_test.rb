# frozen_string_literal: true

require "test_helper"

class ChangeMapTest < Minitest::Test
  def map_for(*paths)
    patch = paths.map { |path| "--- a/#{path}\n+++ b/#{path}\n@@ -1 +1,2 @@\n-old\n+new\n+more\n" }.join
    ThreePassReview::ChangeMap.build(ThreePassReview::Diff.parse(patch))
  end

  def area(map, name)
    map.areas.find { |a| a.name == name } || flunk("no area #{name} in #{map.areas.map(&:name)}")
  end

  def test_counts_files_and_lines_per_area
    map = ThreePassReview::ChangeMap.build(fixture_diff("mixed.patch"))
    models = area(map, "app/models")

    assert_equal [1, 8, 2], [models.files, models.added, models.removed]
    assert_equal({files: 7, added: 15, removed: 5}, map.totals)
  end

  def test_source_roots_split_one_level_deeper
    map = map_for("app/models/a.rb", "app/controllers/b.rb", "lib/x.rb", "lib/sub/y.rb", "docs/z.md", "README.md")

    assert_equal %w[(root) app/controllers app/models docs lib lib/sub], map.areas.map(&:name).sort
  end

  def test_flags_the_kinds_of_change_a_deep_reviewer_cares_about
    map = map_for("db/migrate/20260101_add_index.rb", "Gemfile.lock", "spec/models/invoice_spec.rb",
      ".github/workflows/ci.yml", "infra/main.tf", "docs/guide.md", "src/app.test.ts")

    assert_equal ["migration"], area(map, "db").flags
    assert_equal ["dependencies"], area(map, "(root)").flags
    assert_equal ["tests"], area(map, "spec").flags
    assert_equal ["ci"], area(map, ".github").flags
    assert_equal ["infra"], area(map, "infra").flags
    assert_equal ["docs"], area(map, "docs").flags
    assert_equal ["tests"], area(map, "src").flags
  end

  def test_flags_file_status
    map = ThreePassReview::ChangeMap.build(fixture_diff("mixed.patch"))

    assert_equal %w[deleted new renamed], area(map, "lib").flags
    assert_equal ["binary"], area(map, "(root)").flags
  end

  def test_biggest_areas_come_first
    map = ThreePassReview::ChangeMap.build(fixture_diff("mixed.patch"))

    assert_equal "app/models", map.areas.first.name
  end

  def test_is_frozen_and_serializable
    map = ThreePassReview::ChangeMap.build(fixture_diff("mixed.patch"))

    assert map.frozen?
    assert map.areas.frozen?
    assert_equal map.totals.transform_keys(&:to_s), map.to_h["totals"]
  end
end
