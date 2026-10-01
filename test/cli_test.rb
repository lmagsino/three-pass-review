# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLITest < Minitest::Test
  def test_version_prints_the_version
    out = StringIO.new
    status = ThreePassReview::CLI.new(stdout: out, stderr: StringIO.new).run(["--version"])

    assert_equal 0, status
    assert_equal "threepass #{ThreePassReview::VERSION}\n", out.string
  end
end
