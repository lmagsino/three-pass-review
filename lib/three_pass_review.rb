# frozen_string_literal: true

require_relative "three_pass_review/version"

module ThreePassReview
  class Error < StandardError; end
end

require_relative "three_pass_review/diff"
require_relative "three_pass_review/context_builder"
