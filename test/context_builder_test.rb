# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class ContextBuilderTest < Minitest::Test
  REPO = File.join(FIXTURES, "repo")

  def load_diff(name = "mixed.patch")
    ThreePassReview::Diff.parse(File.read(File.join(FIXTURES, "diffs", name)))
  end

  def builder(**opts)
    ThreePassReview::ContextBuilder.new(repo: REPO, **opts)
  end

  def test_excerpts_cover_hunks_plus_margin_with_numbered_lines
    input = builder(lines_around_hunk: 2).build(diff: load_diff("basic.patch"))
    first, second = input.excerpts

    assert_equal [1, 21], [first.start_line, first.end_line]
    assert_equal [95, 102], [second.start_line, second.end_line]
    assert_includes first.text, " 7+|   def self.sorted(params)\n"
    assert_includes first.text, " 4 | \n"
  end

  def test_overlapping_windows_merge_into_one_excerpt
    input = builder(lines_around_hunk: 50).build(diff: load_diff("basic.patch"))

    assert_equal 1, input.excerpts.size
    assert_equal [1, 102], [input.excerpts.first.start_line, input.excerpts.first.end_line]
  end

  def test_skips_deleted_binary_and_hunkless_files
    paths = builder.build(diff: load_diff).excerpts.map(&:path).uniq

    assert_equal %w[app/models/invoice.rb lib/flag.rb lib/formatting.rb lib/new_name.rb], paths
  end

  def test_loads_conventions_files_that_exist
    input = builder.build(diff: load_diff)

    assert_equal %w[AGENTS.md CONVENTIONS.md], input.conventions.map(&:path)
    assert_includes input.conventions.last.text, "Money.format"
  end

  def test_respects_max_excerpt_bytes
    input = builder(max_excerpt_bytes: 400).build(diff: load_diff)
    total = input.excerpts.sum { |e| e.text.bytesize }

    assert_operator total, :<=, 400
    assert input.excerpts.last.truncated
    refute_empty input.omitted_excerpts
  end

  def test_conventions_respect_their_own_budget
    input = builder(max_conventions_bytes: 50).build(diff: load_diff)

    assert_operator input.conventions.sum { |c| c.text.bytesize }, :<=, 50
    refute input.conventions.first.truncated
    assert input.conventions.last.truncated
  end

  def test_diff_only_mode_has_no_excerpts
    input = builder.build(diff: load_diff, lines_around_hunk: nil)

    assert_empty input.excerpts
    refute input.excerpts?
  end

  def test_base_input_is_deep_frozen
    input = builder.build(diff: load_diff, title: +"Add sorting", body: +"Body")

    assert input.frozen?
    assert input.title.frozen?
    assert input.excerpts.frozen?
    assert input.excerpts.first.text.frozen?
    assert input.conventions.first.text.frozen?
    assert_raises(FrozenError) { input.excerpts << :x }
    assert_raises(FrozenError) { input.title << "x" }
  end

  def test_never_follows_symlinks_inside_the_repo
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "SECRET_TOKEN=abc123\n")
      File.symlink(".env", File.join(dir, "notes.txt"))
      patch = "--- /dev/null\n+++ b/notes.txt\n@@ -0,0 +1 @@\n+SECRET_TOKEN=abc123\n"
      input = ThreePassReview::ContextBuilder.new(repo: dir).build(diff: ThreePassReview::Diff.parse(patch))

      assert_empty input.excerpts
    end
  end

  def test_never_reads_git_internals_even_as_conventions
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "config"), "extraheader = AUTHORIZATION: token\n")
      input = ThreePassReview::ContextBuilder.new(repo: dir, conventions: [".git/config"]).build(diff: load_diff)

      assert_empty input.conventions
    end
  end

  def test_in_a_git_checkout_only_tracked_files_are_read
    Dir.mktmpdir do |dir|
      system("git", "-C", dir, "init", "-q", exception: true)
      File.write(File.join(dir, "CONVENTIONS.md"), "tracked rules\n")
      File.write(File.join(dir, ".env"), "SECRET=1\n")
      system("git", "-C", dir, "add", "CONVENTIONS.md", exception: true)
      input = ThreePassReview::ContextBuilder.new(repo: dir, conventions: %w[CONVENTIONS.md .env]).build(diff: load_diff)

      assert_equal %w[CONVENTIONS.md], input.conventions.map(&:path)
    end
  end

  def test_diff_only_also_drops_conventions
    assert_empty builder.build(diff: load_diff, lines_around_hunk: nil).conventions
  end

  def test_paths_with_nul_bytes_are_skipped
    patch = "--- a/x\0y\n+++ b/x\0y\n@@ -1 +1 @@\n-a\n+b\n"

    assert_empty builder.build(diff: ThreePassReview::Diff.parse(patch)).excerpts
  end

  def test_refuses_paths_that_escape_the_repo
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      File.write(File.join(dir, "secret.txt"), "TOKEN\n")
      File.symlink(File.join(dir, "secret.txt"), File.join(repo, "link.txt"))
      patch = <<~PATCH
        --- a/../secret.txt
        +++ b/../secret.txt
        @@ -1 +1 @@
        -x
        +TOKEN
        --- a/link.txt
        +++ b/link.txt
        @@ -1 +1 @@
        -x
        +TOKEN
      PATCH
      input = ThreePassReview::ContextBuilder.new(repo: repo).build(diff: ThreePassReview::Diff.parse(patch))

      assert_empty input.excerpts
    end
  end
end
