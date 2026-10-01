# frozen_string_literal: true

require "test_helper"

class DiffTest < Minitest::Test
  def parse(name)
    ThreePassReview::Diff.parse(File.read(File.join(FIXTURES, "diffs", name)))
  end

  def test_modified_file_with_two_hunks_maps_new_line_numbers
    diff = parse("basic.patch")
    file = diff.file("app/models/invoice.rb")

    assert_equal :modified, file.status
    assert_equal 2, file.hunks.size
    assert_equal [5, 6, 7, 8, 9, 10, 16], file.hunks.first.added_linenos
    assert_equal [100], file.hunks.last.added_linenos
    assert_equal "class Invoice < ApplicationRecord", file.hunks.first.section
  end

  def test_deleted_lines_keep_old_numbers_only
    line = parse("basic.patch").files.first.hunks.first.lines.find { |l| l.type == :del }

    assert_equal "    line_items.sum(&:amount)", line.text
    assert_equal 10, line.old_lineno
    assert_nil line.new_lineno
  end

  def test_every_kind_of_file_change
    diff = parse("mixed.patch")
    statuses = diff.files.to_h { |f| [f.path, f.status] }

    assert_equal({
      "app/models/invoice.rb" => :modified,
      "lib/flag.rb" => :added,
      "lib/formatting.rb" => :added,
      "lib/legacy.rb" => :deleted,
      "lib/new_name.rb" => :renamed,
      "lib/sub/moved.rb" => :renamed,
      "logo.png" => :modified
    }, statuses)
  end

  def test_rename_keeps_old_path_and_its_hunk
    file = parse("mixed.patch").file("lib/new_name.rb")

    assert_equal "lib/old_name.rb", file.old_path
    assert_equal [2], file.added_linenos
  end

  def test_pure_rename_has_no_hunks
    file = parse("mixed.patch").file("lib/sub/moved.rb")

    assert_equal "lib/moved.rb", file.old_path
    assert_empty file.hunks
  end

  def test_deleted_file_has_no_new_path
    file = parse("mixed.patch").files.find { |f| f.old_path == "lib/legacy.rb" }

    assert_nil file.new_path
    assert file.deleted?
  end

  def test_binary_files_are_flagged_in_both_git_formats
    assert parse("mixed.patch").file("logo.png").binary?
    assert parse("full.patch").file("logo.png").binary?
  end

  def test_binary_patch_payload_is_not_parsed_as_files
    assert_equal parse("mixed.patch").paths, parse("full.patch").paths
  end

  def test_no_newline_marker_is_not_a_line
    hunk = parse("mixed.patch").file("lib/flag.rb").hunks.first

    assert_equal 1, hunk.lines.size
    assert_equal "no trailing newline", hunk.lines.first.text
  end

  def test_plain_unified_diff_without_git_header
    file = parse("plain_unified.patch").files.first

    assert_equal "lib/plain.rb", file.path
    assert_equal [2], file.added_linenos
  end

  def test_content_lines_that_look_like_file_headers
    diff = parse("dashes.patch")
    lines = diff.files.first.hunks.first.lines

    assert_equal 1, diff.files.size
    assert_equal [:context, :del, :add, :context], lines.map(&:type)
    assert_equal "-- old comment", lines[1].text
    assert_equal "++ new marker", lines[2].text
  end

  def test_covers_checks_hunks_plus_margin
    file = parse("basic.patch").file("app/models/invoice.rb")

    assert file.covers?(6, 6)
    assert file.covers?(20, 22, margin: 3) # hunk ends at 19
    refute file.covers?(23, 24, margin: 3)
    refute file.covers?(50, 60)
  end

  def test_truncated_hunk_is_an_error
    text = File.read(File.join(FIXTURES, "diffs", "basic.patch")).lines[0..8].join

    assert_raises(ThreePassReview::Diff::ParseError) { ThreePassReview::Diff.parse(text) }
  end

  def test_empty_input_has_no_files
    assert ThreePassReview::Diff.parse("").empty?
  end

  def test_parsed_diff_is_frozen
    diff = parse("basic.patch")

    assert diff.frozen?
    assert diff.files.frozen?
    assert diff.files.first.hunks.first.lines.frozen?
  end
end
