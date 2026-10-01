# frozen_string_literal: true

require "test_helper"

class ReconcilerTest < Minitest::Test
  def result(pass, *findings, sample: 1)
    ThreePassReview::PassResult.new(pass: pass, sample: sample, findings: findings, input_tokens: 0, output_tokens: 0,
      stop_reason: "end_turn", error: nil)
  end

  def only(list)
    assert_equal 1, list.size, "expected exactly one finding, got #{list.size}"
    list.first
  end

  def f(**overrides)
    finding_hash(**overrides)
  end

  def reconcile(*results, **opts)
    ThreePassReview::Reconciler.new(diff: fixture_diff, confidence_threshold: 0.6, max_comments: 10, merge_line_gap: 3, **opts)
      .reconcile(results)
  end

  def test_cross_pass_agreement_merges_and_raises_confidence
    out = reconcile(
      result("security", f(confidence: 0.9)),
      result("correctness", f(category: "correctness", subcategory: "logic_error", title: "User input interpolated into SQL query", confidence: 0.5))
    )
    merged = only(out.findings)

    assert_equal %w[correctness security], merged.passes
    assert_in_delta 0.95, merged.confidence # 1 - 0.1 * 0.5
    assert_equal "security", merged.category
  end

  def test_adjacent_lines_merge_within_the_gap_only
    near = reconcile(result("security", f(line_start: 5, line_end: 5)), result("correctness", f(line_start: 8, line_end: 8)))
    far = reconcile(result("security", f(line_start: 5, line_end: 5)), result("correctness", f(line_start: 9, line_end: 9)))

    assert_equal 1, near.findings.size
    assert_equal 2, far.findings.size
  end

  def test_different_files_never_merge
    diff = fixture_diff("mixed.patch")
    out = ThreePassReview::Reconciler.new(diff: diff).reconcile([
      result("security", f(file: "lib/new_name.rb", line_start: 2, line_end: 2)),
      result("correctness", f(file: "lib/formatting.rb", line_start: 2, line_end: 2))
    ])

    assert_equal 2, out.findings.size
  end

  def test_same_lines_with_a_different_subcategory_and_title_stay_apart
    out = reconcile(
      result("security", f(subcategory: "sql_injection", title: "User input interpolated into SQL")),
      result("correctness", f(subcategory: "nil_handling", title: "Nil sort param raises", category: "correctness"))
    )

    assert_equal 2, out.findings.size
  end

  def test_same_subcategory_merges_even_with_different_titles
    out = reconcile(result("security", f(title: "SQL injection")), result("correctness", f(title: "Unsafe ORDER BY")))

    assert_equal 1, out.findings.size
  end

  def test_a_pass_repeating_itself_is_counted_once
    out = reconcile(result("security", f(confidence: 0.7), f(confidence: 0.6, line_start: 7, line_end: 8)))
    merged = only(out.findings)

    assert_equal %w[security], merged.passes
    assert_in_delta 0.7, merged.confidence
  end

  def test_combined_confidence_is_capped
    out = reconcile(result("security", f(confidence: 1.0)), result("correctness", f(confidence: 1.0)))

    assert_in_delta 0.99, only(out.findings).confidence
  end

  def test_merge_keeps_highest_severity_narrowest_range_and_distinct_evidence
    out = reconcile(
      result("security", f(severity: "medium", line_start: 7, line_end: 9, evidence: "order(...)")),
      result("correctness", f(severity: "critical", line_start: 8, line_end: 8, evidence: "order(...)")),
      result("architecture", f(severity: "low", line_start: 6, line_end: 10, evidence: "def self.sorted"))
    )
    merged = only(out.findings)

    assert_equal "critical", merged.severity
    assert_equal [8, 8], [merged.line_start, merged.line_end]
    assert_equal ["order(...)", "def self.sorted"], merged.evidence
  end

  def test_clusters_are_transitive
    out = reconcile(
      result("security", f(line_start: 5, line_end: 5)),
      result("correctness", f(line_start: 8, line_end: 8)),
      result("architecture", f(line_start: 11, line_end: 11))
    )

    assert_equal 1, out.findings.size
  end

  def test_threshold_drops_and_counts_low_confidence
    out = reconcile(result("security", f(confidence: 0.59), f(line_start: 16, line_end: 16, subcategory: "x", title: "Other", confidence: 0.6)))

    assert_equal 1, out.findings.size
    assert_equal 1, out.below_threshold
  end

  def test_ranks_by_severity_then_confidence_then_agreement
    out = reconcile(
      result("security",
        f(line_start: 5, line_end: 5, subcategory: "a", title: "Alpha", severity: "medium", confidence: 0.99),
        f(line_start: 16, line_end: 16, subcategory: "b", title: "Bravo", severity: "high", confidence: 0.7),
        f(line_start: 100, line_end: 100, subcategory: "c", title: "Charlie", severity: "high", confidence: 0.8)),
      result("correctness", f(line_start: 16, line_end: 16, subcategory: "b", title: "Bravo", severity: "high", confidence: 0.1))
    )

    assert_equal %w[Charlie Bravo Alpha], out.findings.map(&:title)
  end

  def test_caps_the_number_of_findings
    many = (1..4).map { |i| f(line_start: [5, 16, 100, 8][i - 1], line_end: [5, 16, 100, 8][i - 1], subcategory: "s#{i}", title: "T#{i}") }
    out = reconcile(result("security", *many), max_comments: 2)

    assert_equal 2, out.findings.size
    assert_equal 2, out.cut
  end

  def test_invalid_findings_are_counted_with_reasons
    out = reconcile(result("security", f, f(file: "nope.rb"), f(confidence: 2)))

    assert_equal 2, out.dropped_invalid
    assert_equal ["file not in diff", "confidence outside 0..1"], out.invalid.map(&:reason)
  end

  def test_samples_of_one_pass_count_as_separate_sources
    out = reconcile(result("combined", f(confidence: 0.5), sample: 1), result("combined", f(confidence: 0.5), sample: 2))
    merged = only(out.findings)

    assert_equal %w[combined#1 combined#2], merged.passes
    assert_in_delta 0.75, merged.confidence
  end

  def test_result_is_frozen_and_order_independent
    a = reconcile(result("security", f(confidence: 0.9)), result("correctness", f(confidence: 0.7)))
    b = reconcile(result("correctness", f(confidence: 0.7)), result("security", f(confidence: 0.9)))

    assert a.frozen?
    assert_equal a.findings, b.findings
  end
end
