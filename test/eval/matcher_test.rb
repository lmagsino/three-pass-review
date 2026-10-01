# frozen_string_literal: true

require_relative "eval_helper"

class MatcherTest < Minitest::Test
  def matcher = ThreePassReview::Eval::Matcher.new(gap: 3)

  def test_strict_needs_file_lines_and_category
    assert_equal ["d1"], matcher.strict([eval_finding], [defect]).caught
    assert_empty matcher.strict([eval_finding(category: "correctness")], [defect]).caught
    assert_empty matcher.strict([eval_finding(file: "other.rb")], [defect]).caught
  end

  def test_lenient_ignores_category
    assert_equal ["d1"], matcher.lenient([eval_finding(category: "correctness")], [defect]).caught
  end

  def test_lines_may_be_up_to_three_apart
    assert_equal ["d1"], matcher.strict([eval_finding(lines: [11, 12])], [defect]).caught
    assert_empty matcher.strict([eval_finding(lines: [12, 13])], [defect]).caught
    assert_equal ["d1"], matcher.strict([eval_finding(lines: [1, 5])], [defect]).caught
  end

  def test_one_finding_matches_at_most_one_defect
    result = matcher.strict([eval_finding], [defect(id: "d1"), defect(id: "d2")])

    assert_equal ["d1"], result.caught
    assert_equal [0], result.matched_findings
  end

  def test_a_defect_is_caught_once
    result = matcher.strict([eval_finding(title: "A"), eval_finding(title: "B")], [defect])

    assert_equal ["d1"], result.caught
    assert_equal [0], result.matched_findings
  end
end
