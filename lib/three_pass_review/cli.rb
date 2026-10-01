# frozen_string_literal: true

require "optparse"

module ThreePassReview
  class CLI
    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      if argv.include?("--version") || argv.include?("-v")
        @stdout.puts "threepass #{VERSION}"
        return 0
      end

      @stderr.puts "usage: threepass --version"
      1
    end
  end
end
