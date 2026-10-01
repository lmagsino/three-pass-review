# frozen_string_literal: true

require "test_helper"

class PromptsTest < Minitest::Test
  def test_every_prompt_has_a_sha256_hash
    hashes = ThreePassReview::Prompts.hashes

    assert_equal %w[shared correctness security architecture combined brief], hashes.keys
    hashes.each_value { |h| assert_match(/\Asha256:\h{64}\z/, h) }
  end

  def test_shared_rules_cover_untrusted_input_rubric_and_empty_answers
    shared = ThreePassReview::Prompts.read("shared")

    assert_includes shared, "untrusted data"
    assert_includes shared, "prompt_injection"
    %w[0.9 0.6 0.3].each { |score| assert_includes shared, "**#{score}**" }
    assert_includes shared, "Finding nothing is a valid answer"
  end

  def test_version_is_short_and_stable
    assert_match(/\A\h{12}\z/, ThreePassReview::Prompts.version)
    assert_equal ThreePassReview::Prompts.version, ThreePassReview::Prompts.version
  end

  def test_unknown_prompt_is_refused
    assert_raises(ArgumentError) { ThreePassReview::Prompts.read("../../etc/passwd") }
  end
end
