# frozen_string_literal: true

require "json"
require_relative "three_pass_review/version"

module ThreePassReview
  class Error < StandardError; end
end

require_relative "three_pass_review/diff"
require_relative "three_pass_review/context_builder"
require_relative "three_pass_review/prompts"
require_relative "three_pass_review/finding"
require_relative "three_pass_review/llm/client"
require_relative "three_pass_review/llm/anthropic_client"
require_relative "three_pass_review/llm/fake_client"
require_relative "three_pass_review/passes/base"
require_relative "three_pass_review/runner"
require_relative "three_pass_review/config"
require_relative "three_pass_review/budget"
require_relative "three_pass_review/review"
