# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "open3"
require "fileutils"
require "rbconfig"

class CLITest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")
  REPO = File.join(FIXTURES, "repo")
  PATCH = File.join(FIXTURES, "diffs", "basic.patch")
  ROOT = File.expand_path("..", __dir__)

  def cli(*argv, env: {"THREEPASS_FAKE" => BASIC}, stdin: "")
    out = StringIO.new
    err = StringIO.new
    status = ThreePassReview::CLI.new(stdin: StringIO.new(stdin), stdout: out, stderr: err, env: env).run(argv)
    [status, out.string, err.string]
  end

  def review(*extra, **kw)
    cli("review", "--diff", PATCH, "--repo", REPO, "--title", "Add sortable invoices", *extra, **kw)
  end

  def test_version_prints_the_version
    status, out, = cli("--version")

    assert_equal 0, status
    assert_equal "threepass #{ThreePassReview::VERSION}\n", out
  end

  def test_help_lists_the_flags
    status, out, = cli("--help")

    assert_equal 0, status
    %w[--diff --title --body-file --repo --config --format --mode --fail-on --no-cost-ceiling].each { |flag| assert_includes out, flag }
  end

  def test_review_prints_the_markdown_comment
    status, out, = review

    assert_equal 0, status
    assert out.start_with?("<!-- threepass -->")
    assert_includes out, "### threepass: 4 findings (1 high)"
  end

  def test_json_format
    status, out, = review("--format", "json")

    assert_equal 0, status
    assert_equal "independent", JSON.parse(out)["mode"]
  end

  def test_diff_from_stdin_and_body_file
    Dir.mktmpdir do |dir|
      body = File.join(dir, "pr.md")
      File.write(body, "Sorts invoices.")
      status, out, = cli("review", "--diff", "-", "--repo", REPO, "--body-file", body, stdin: File.read(PATCH))

      assert_equal 0, status
      assert_includes out, "User input interpolated into SQL"
    end
  end

  def test_fail_on_exits_two_when_a_finding_is_severe_enough
    assert_equal 2, review("--fail-on", "high").first
    assert_equal 2, review("--fail-on", "low").first
    assert_equal 0, review("--fail-on", "critical").first
  end

  def test_every_mode_runs
    ThreePassReview::Runner::MODES.each do |mode|
      assert_equal 0, review("--mode", mode).first, mode
    end
  end

  def test_refused_by_the_ceiling_exits_three_and_says_why
    Dir.mktmpdir do |dir|
      config = File.join(dir, "tiny.yml")
      File.write(config, "max_cost_usd: 0.0001\n")
      status, out, err = review("--config", config)

      assert_equal 3, status
      assert_includes out, "### threepass: not run"
      assert_match(/refused: estimated cost/, err)
      assert_equal 3, review("--config", config, "--format", "json").first
    end
  end

  def test_missing_pricing_refuses_unless_the_ceiling_is_off
    Dir.mktmpdir do |dir|
      config = File.join(dir, "unpriced.yml")
      File.write(config, "model: claude-unpriced\n")

      assert_equal 3, review("--config", config).first
      status, out, = review("--config", config, "--no-cost-ceiling")
      assert_equal 0, status
      assert_includes out, "Cost unknown"
    end
  end

  def test_reads_threepass_yml_from_the_repo_by_default
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir[File.join(REPO, "*")], dir)
      File.write(File.join(dir, ".threepass.yml"), "max_cost_usd: 0.0001\n")

      assert_equal 3, cli("review", "--diff", PATCH, "--repo", dir).first
    end
  end

  def test_errors_exit_one
    assert_equal 1, cli("review").first
    assert_equal 1, cli("review", "--diff", "/nonexistent.patch").first
    assert_equal 1, cli("review", "--diff", PATCH, "--format", "html").first
    assert_equal 1, cli("review", "--diff", PATCH, "--repo", "/nonexistent").first
    assert_equal 1, cli("deploy").first
    assert_equal 1, cli("review", "--diff", "-", stdin: "@@ -1 +1 @@\n").first
  end

  def test_without_a_key_or_fake_it_exits_one
    status, _, err = review(env: {})

    assert_equal 1, status
    assert_match(/ANTHROPIC_API_KEY is not set/, err)
  end

  def test_every_pass_failing_exits_one
    Dir.mktmpdir do |dir|
      %w[correctness security architecture].each do |pass|
        File.write(File.join(dir, "#{pass}.json"), JSON.generate("error" => "cut off", "usage" => {"input_tokens" => 1, "output_tokens" => 1}))
      end
      status, out, err = review(env: {"THREEPASS_FAKE" => dir})

      assert_equal 1, status
      assert_includes out, "pass failed"
      assert_match(/every pass failed/, err)
    end
  end

  def test_the_executable_runs_end_to_end
    env = {"THREEPASS_FAKE" => BASIC, "ANTHROPIC_API_KEY" => nil}
    out, err, status = Open3.capture3(env, RbConfig.ruby, File.join(ROOT, "exe", "threepass"),
      "review", "--diff", PATCH, "--repo", REPO, "--format", "json", chdir: ROOT)

    assert status.success?, err
    assert_equal 4, JSON.parse(out)["findings"].size
  end
end
