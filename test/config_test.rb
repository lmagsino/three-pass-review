# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  def config(overrides = {})
    ThreePassReview::Config.new(overrides)
  end

  def test_defaults
    c = config

    assert_equal "claude-sonnet-5-5", c.model
    assert_in_delta 0.50, c.max_cost_usd
    assert_equal 4000, c.max_output_tokens
    assert_equal %w[correctness security architecture], c.enabled_passes
    assert_equal [30, 5, 60_000], [c.lines_around_hunk, c.reduced_lines_around_hunk, c.max_excerpt_bytes]
  end

  def test_default_prices_and_model_ids_are_dated
    text = File.read(ThreePassReview::Config::DEFAULTS_PATH)

    assert_match(%r{Copied from https://platform.claude.com/docs/en/about-claude/pricing on \d{4}-\d{2}-\d{2}}, text)
    assert_match(%r{Checked against https://platform.claude.com/docs/en/about-claude/models/overview on \d{4}-\d{2}-\d{2}}, text)
    assert_equal({input: 2.0, output: 10.0}, config.pricing_for("claude-sonnet-5-5"))
  end

  def test_overrides_merge_deeply
    c = config("passes" => {"architecture" => {"enabled" => false}}, "context" => {"lines_around_hunk" => 10})

    assert_equal %w[correctness security], c.enabled_passes
    assert_equal 10, c.lines_around_hunk
    assert_equal 60_000, c.max_excerpt_bytes
    assert_includes c.conventions, "CLAUDE.md"
  end

  def test_unknown_keys_are_refused
    error = assert_raises(ThreePassReview::Config::Invalid) { config("max_cost" => 1) }
    assert_match(/unknown config key max_cost/, error.message)
    assert_raises(ThreePassReview::Config::Invalid) { config("context" => {"lines" => 3}) }
    assert_raises(ThreePassReview::Config::Invalid) { config("passes" => {"style" => {"enabled" => true}}) }
  end

  def test_invalid_values_are_refused
    [
      {"max_cost_usd" => 0}, {"max_cost_usd" => "1"}, {"confidence_threshold" => 1.5},
      {"effort" => "extreme"}, {"max_output_tokens" => 0}, {"merge_line_gap" => -1},
      {"passes" => {"correctness" => {"enabled" => false}, "security" => {"enabled" => false}, "architecture" => {"enabled" => false}}},
      {"pricing" => {"x" => {"input" => "cheap", "output" => 1}}}
    ].each do |bad|
      assert_raises(ThreePassReview::Config::Invalid, bad.inspect) { config(bad) }
    end
  end

  def test_wrong_shapes_are_config_errors_not_crashes
    [
      {"passes" => nil}, {"passes" => {"correctness" => true}}, {"context" => "big"},
      {"passes" => {"correctness" => {"enabled" => "yes"}}},
      {"passes" => {"architecture" => {"conventions" => [1]}}},
      {"passes" => {"architecture" => {"conventions" => ["/etc/passwd"]}}},
      {"passes" => {"architecture" => {"conventions" => ["../secrets.md"]}}}
    ].each do |bad|
      assert_raises(ThreePassReview::Config::Invalid, bad.inspect) { config(bad) }
    end
  end

  def test_missing_or_null_pricing_is_nil
    assert_nil config("model" => "claude-new-model").pricing_for
    assert_nil config("pricing" => {"claude-sonnet-5-5" => {"input" => nil, "output" => nil}}).pricing_for
  end

  def test_effort_can_be_null
    assert_nil config("effort" => nil).effort
  end

  def test_load_reads_yaml_safely
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".threepass.yml")
      File.write(path, "max_cost_usd: 0.25\npricing:\n  my-model: { input: 1, output: 2 }\n")
      assert_in_delta 0.25, ThreePassReview::Config.load(path).max_cost_usd

      File.write(path, "--- !ruby/object:OpenStruct\nfoo: 1\n")
      assert_raises(ThreePassReview::Config::Invalid) { ThreePassReview::Config.load(path) }
    end
  end

  def test_missing_file_is_an_error
    assert_raises(ThreePassReview::Config::Invalid) { ThreePassReview::Config.load("/nonexistent/.threepass.yml") }
  end

  def test_brief_is_off_by_default_and_must_be_boolean
    refute config.brief_enabled?
    assert config("brief" => {"enabled" => true}).brief_enabled?
    assert_raises(ThreePassReview::Config::Invalid) { config("brief" => {"enabled" => "yes"}) }
  end
end
