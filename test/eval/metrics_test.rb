# frozen_string_literal: true

require_relative "eval_helper"

class MetricsTest < Minitest::Test
  M = ThreePassReview::Eval::Metrics

  # Reference values computed from the Wilson score formula with z = 1.96.
  def test_wilson_interval
    lo, hi = M.wilson(5, 10)
    assert_in_delta 0.2366, lo, 0.0001
    assert_in_delta 0.7634, hi, 0.0001

    lo, hi = M.wilson(0, 10)
    assert_in_delta 0.0, lo
    assert_in_delta 0.2775, hi, 0.0001

    lo, hi = M.wilson(10, 10)
    assert_in_delta 0.7225, lo, 0.0001
    assert_in_delta 1.0, hi
  end

  def test_wilson_is_nil_without_data
    assert_nil M.wilson(0, 0)
  end

  def test_percentile_interpolates
    assert_in_delta 2.5, M.percentile([1, 2, 3, 4], 50)
    assert_in_delta 3.7, M.percentile([1, 2, 3, 4], 90)
    assert_nil M.percentile([], 50)
    assert_in_delta 7, M.percentile([7], 90)
  end

  def test_proportion
    assert_equal({"k" => 3, "n" => 4, "rate" => 0.75, "ci95" => M.wilson(3, 4)}, M.proportion(3, 4))
    assert_nil M.proportion(0, 0)["rate"]
  end
end
