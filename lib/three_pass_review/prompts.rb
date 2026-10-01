# frozen_string_literal: true

require "digest"

module ThreePassReview
  # Prompts are versioned files; their hashes go into every output and eval
  # run, so a result can always be traced to the exact prompt text.
  module Prompts
    DIR = File.expand_path("prompts", __dir__)
    NAMES = %w[shared correctness security architecture combined brief].freeze

    class << self
      def read(name)
        raise ArgumentError, "unknown prompt #{name}" unless NAMES.include?(name.to_s)

        cache[name.to_s] ||= File.read(File.join(DIR, "#{name}.md")).freeze
      end

      def hashes
        NAMES.to_h { |name| [name, "sha256:#{Digest::SHA256.hexdigest(read(name))}"] }
      end

      # One short identifier for the whole prompt set.
      def version
        Digest::SHA256.hexdigest(hashes.values.join("\n"))[0, 12]
      end

      private

      def cache
        @cache ||= {}
      end
    end
  end
end
