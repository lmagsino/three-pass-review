# frozen_string_literal: true

require "test_helper"

class BriefTest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")

  def data
    JSON.parse(File.read(File.join(BASIC, "brief.json"))).except("usage")
  end

  def test_valid_brief
    brief, reason = ThreePassReview::Brief.from(data, diff: fixture_diff)

    assert_nil reason
    assert_match(/Adds sorting/, brief.summary)
    assert_equal %w[api_contract behavior], brief.impact.map { |i| i["kind"] }
    assert brief.frozen?
  end

  def test_review_order_outside_the_diff_is_dropped_and_counted
    brief, = ThreePassReview::Brief.from(data, diff: fixture_diff)

    assert_equal [[7, 9], [100, 100]], brief.review_order.map { |e| [e["line_start"], e["line_end"]] }
    assert_equal 1, brief.dropped_review_order
  end

  def test_missing_summary_or_non_object_is_rejected
    assert_equal [nil, "summary missing"], ThreePassReview::Brief.from(data.merge("summary" => " "), diff: fixture_diff)
    assert_equal [nil, "reply was not an object"], ThreePassReview::Brief.from([], diff: fixture_diff)
  end

  def test_malformed_parts_are_dropped_not_fatal
    messy = data.merge("risks" => ["ok", 3, nil], "impact" => [{"kind" => "vibes", "description" => "x"}], "questions" => "one")
    brief, = ThreePassReview::Brief.from(messy, diff: fixture_diff)

    assert_equal ["ok"], brief.risks
    assert_empty brief.impact
    assert_empty brief.questions
  end

  def test_lists_are_capped
    many = data.merge("questions" => (1..9).map { |i| "q#{i}" })

    assert_equal 5, ThreePassReview::Brief.from(many, diff: fixture_diff).first.questions.size
  end

  def test_schema_closes_every_object_and_has_no_numeric_bounds
    json = JSON.generate(ThreePassReview::Brief.schema)

    refute_match(/minimum|maximum|minLength|maxLength|minItems|maxItems/, json)
    assert_equal json.scan('"type":"object"').size, json.scan('"additionalProperties":false').size
  end
end
