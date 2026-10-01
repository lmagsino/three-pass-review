# frozen_string_literal: true

require_relative "eval_helper"

# The published dataset must always validate: schema, licenses, diffs that
# apply to their context, and defects inside changed hunks.
class DatasetTest < Minitest::Test
  ROOT_CASES = File.expand_path("../../evals/cases", __dir__)

  def test_every_dataset_case_is_valid
    cases = ThreePassReview::Eval::Dataset.load(ROOT_CASES)
    skip "no cases yet" if cases.empty?

    cases.each { |c| assert c.valid?, "#{c.id}: #{c.problems.join("; ")}" }
  end
end
