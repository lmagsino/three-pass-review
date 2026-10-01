# frozen_string_literal: true

require "test_helper"

class FindingTest < Minitest::Test
  def validate(**overrides)
    ThreePassReview::Finding.validate(finding_hash(**overrides), diff: fixture_diff, pass: "security")
  end

  def test_valid_finding
    finding, reason = validate

    assert_nil reason
    assert_equal "security", finding.pass
    assert_equal "app/models/invoice.rb:8", finding.location
    assert finding.frozen?
  end

  def test_rejects_missing_fields
    hash = finding_hash
    hash.delete("evidence")
    _, reason = ThreePassReview::Finding.validate(hash, diff: fixture_diff, pass: "security")

    assert_equal "missing evidence", reason
  end

  def test_rejects_file_not_in_diff
    assert_equal "file not in diff", validate(file: "app/models/user.rb").last
  end

  def test_rejects_lines_outside_hunks_plus_margin
    assert_nil validate(line_start: 22, line_end: 22).last # hunk ends at 19, margin 3
    assert_equal "lines outside the changed hunks", validate(line_start: 40, line_end: 41).last
  end

  def test_rejects_bad_values
    assert_equal "invalid line range", validate(line_start: 9, line_end: 8).last
    assert_equal "invalid line range", validate(line_start: "8").last
    assert_equal "confidence outside 0..1", validate(confidence: 1.5).last
    assert_equal "urgent is not a severity", validate(severity: "urgent").last
    assert_equal "style is not a category", validate(category: "style").last
    assert_equal "title not a string", validate(title: nil).last
  end

  def test_rejects_findings_on_deleted_files
    diff = fixture_diff("mixed.patch")
    hash = finding_hash(file: "lib/legacy.rb", line_start: 1, line_end: 1)

    assert_equal "file not in diff", ThreePassReview::Finding.validate(hash, diff: diff, pass: "security").last
  end

  def test_schema_has_no_numeric_bounds_and_closes_objects
    schema = ThreePassReview::Finding.schema(%w[security])
    item = schema[:properties][:findings][:items]

    assert_equal false, schema[:additionalProperties]
    assert_equal false, item[:additionalProperties]
    assert_equal %w[security], item[:properties][:category][:enum]
    refute JSON.generate(schema).match?(/minimum|maximum|minLength|maxLength/)
  end
end
