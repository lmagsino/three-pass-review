# frozen_string_literal: true

require_relative "lib/three_pass_review/version"

Gem::Specification.new do |spec|
  spec.name = "three_pass_review"
  spec.version = ThreePassReview::VERSION
  spec.authors = ["Leo Magsino Jr"]
  spec.summary = "Reviews a diff with three independent AI passes under a hard cost ceiling."
  spec.description = "threepass runs correctness, security and architecture passes on a diff, " \
    "reconciles their findings into one comment, and reports what the review cost."
  spec.homepage = "https://github.com/lmagsino/three-pass-review"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["threepass"]
  spec.require_paths = ["lib"]
end
