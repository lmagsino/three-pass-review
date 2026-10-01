# frozen_string_literal: true

require "yaml"
require "digest"
require "fileutils"

module ThreePassReview
  module Eval
    # Human labels for findings that matched no known defect. A label is keyed
    # by a hash of the case, file, lines and title, so it carries over to any
    # later run that reports the same finding.
    class Labels
      VALUES = %w[unlabeled real false_positive nitpick unclear].freeze

      def self.key(case_id, finding)
        title = finding["title"].to_s.downcase.split.join(" ")
        parts = [case_id, finding["file"], finding["line_start"], finding["line_end"], title]
        Digest::SHA256.hexdigest(parts.join("\0"))[0, 16]
      end

      # The same finding can appear in several runs' files. Two different
      # labels for it are an error rather than "newest file wins", because
      # file times differ between clones and so would the published precision.
      def initialize(dir)
        @dir = dir
        @known = {}
        source = {}
        Dir[File.join(dir, "*.yml")].sort.each do |path|
          (YAML.safe_load_file(path) || {}).fetch("findings", []).each do |entry|
            label = entry["label"].to_s
            raise Error, "#{path}: unknown label #{label.inspect} (use #{VALUES.join(", ")})" unless VALUES.include?(label)
            next if label == "unlabeled"

            key = entry["key"]
            if @known.key?(key) && @known[key] != label
              raise Error, "finding #{key} is labeled #{@known[key]} in #{source[key]} but #{label} in #{path}; make them agree"
            end
            @known[key] = label
            source[key] = path
          end
        end
      end

      def label(key)
        @known.fetch(key, "unlabeled")
      end

      # entries: hashes with key, case, file, lines, title, from. Labels
      # already given to the same key are filled in.
      def write(run_id, entries)
        FileUtils.mkdir_p(@dir)
        path = File.join(@dir, "#{run_id}.yml")
        findings = entries.map { |e| e.merge("label" => label(e["key"]), "note" => "") }
        header = "# Label each finding: real, false_positive, nitpick or unclear. See docs/eval-design.md#labeling-what-makes-precision-honest\n"
        File.write(path, header + YAML.dump("run" => run_id, "findings" => findings))
        path
      end
    end
  end
end
