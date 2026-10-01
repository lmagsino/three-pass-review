# frozen_string_literal: true

require "yaml"
require "date"
require "digest"

module ThreePassReview
  module Eval
    Defect = Data.define(:id, :file, :line_start, :line_end, :category, :subcategory, :severity, :description)

    # One dataset case: evals/cases/<id>/ with case.yml, diff.patch and
    # context/ (head-version copies of the changed files).
    class Case
      KINDS = %w[real planted clean].freeze
      LICENSES = %w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause].freeze
      SOURCE_KEYS = %w[repo license pr introduced_by merged_at].freeze
      DEFECT_KEYS = %w[id file lines category subcategory severity description].freeze

      attr_reader :id, :dir, :data, :diff_text

      def self.load(dir)
        new(dir)
      end

      def initialize(dir)
        @dir = dir
        @id = File.basename(dir)
        path = File.join(dir, "case.yml")
        @data = File.file?(path) ? (YAML.safe_load_file(path, permitted_classes: [Date]) || {}) : {}
        diff_path = File.join(dir, "diff.patch")
        @diff_text = File.file?(diff_path) ? File.read(diff_path) : nil
      rescue Psych::Exception => e
        @data = {"_yaml_error" => e.message}
      end

      def kind = data["kind"]
      def language = data["language"]
      def source = data["source"] || {}
      def title = data.dig("pr", "title").to_s
      def body = data.dig("pr", "body").to_s
      def context_dir = File.join(dir, "context")

      def merged_at
        value = source["merged_at"]
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      def diff
        @diff ||= Diff.parse(diff_text.to_s)
      end

      def defects
        @defects ||= Array(data["defects"]).map do |d|
          lines = Array(d["lines"])
          Defect.new(id: d["id"], file: d["file"], line_start: lines[0], line_end: lines[1] || lines[0],
            category: d["category"], subcategory: d["subcategory"], severity: d["severity"], description: d["description"])
        end
      end

      # Every reason this case can't be used; empty when it's valid.
      def problems
        return ["case.yml is not valid YAML: #{data["_yaml_error"]}"] if data["_yaml_error"]
        return ["case.yml is missing"] if data.empty?

        list = []
        list << "id #{data["id"].inspect} doesn't match the directory name" unless data["id"] == id
        list << "kind must be one of #{KINDS.join(", ")}" unless KINDS.include?(kind)
        list << "language is missing" if language.to_s.empty?
        list.concat(source_problems)
        list << "pr.title is missing" if title.empty?
        list.concat(defect_problems)
        list.concat(diff_problems)
        list
      end

      def valid?
        problems.empty?
      end

      private

      def source_problems
        list = SOURCE_KEYS.reject { |k| source[k].to_s.strip != "" }.map { |k| "source.#{k} is missing" }
        if source["license"] && !LICENSES.include?(source["license"])
          list << "source.license #{source["license"]} is not permissive (#{LICENSES.join(", ")})"
        end
        list << "source.merged_at is not a date" if source["merged_at"] && merged_at.nil?
        list << "source.fixed_by is required for real cases" if kind == "real" && source["fixed_by"].to_s.strip.empty?
        list << "notes must say how the bug was planted" if kind == "planted" && data["notes"].to_s.strip.empty?
        list
      end

      def defect_problems
        list = []
        count = Array(data["defects"]).size
        list << "clean cases have no defects" if kind == "clean" && count.positive?
        list << "planted cases have exactly one defect" if kind == "planted" && count != 1
        list << "real cases need at least one defect" if kind == "real" && count.zero?
        Array(data["defects"]).each_with_index do |d, i|
          missing = DEFECT_KEYS.reject { |k| d.is_a?(Hash) && d.key?(k) }
          list << "defect #{i + 1} is missing #{missing.join(", ")}" if missing.any?
        end
        return list if list.any?

        defects.each do |d|
          list << "defect #{d.id}: category #{d.category} is unknown" unless Finding::CATEGORIES.include?(d.category)
          list << "defect #{d.id}: severity #{d.severity} is unknown" unless Finding::SEVERITIES.include?(d.severity)
          unless d.line_start.is_a?(Integer) && d.line_end.is_a?(Integer) && d.line_end >= d.line_start
            list << "defect #{d.id}: lines must be [start, end]"
          end
        end
        list
      end

      def diff_problems
        return ["diff.patch is missing"] if diff_text.nil?

        list = []
        begin
          return ["diff.patch has no files"] if diff.empty?
        rescue Diff::ParseError => e
          return ["diff.patch doesn't parse: #{e.message}"]
        end
        defects.each do |d|
          file = diff.file(d.file)
          next list << "defect #{d.id}: #{d.file} is not in the diff" if file.nil?
          next unless d.line_start.is_a?(Integer) && d.line_end.is_a?(Integer)

          list << "defect #{d.id}: lines #{d.line_start}-#{d.line_end} are not inside a changed hunk" unless file.covers?(d.line_start, d.line_end)
        end
        list.concat(context_problems)
      end

      # The diff must apply to the context: every added line has to be in the
      # head-version copy at the line number the diff gives it.
      def context_problems
        diff.files.reject { |f| f.deleted? || f.binary? }.flat_map do |file|
          path = File.join(context_dir, file.path)
          next ["context/#{file.path} is missing"] unless File.file?(path)

          lines = File.read(path).lines.map(&:chomp)
          bad = file.hunks.flat_map(&:lines).select { |l| l.type == :add && lines[l.new_lineno - 1] != l.text }
          bad.empty? ? [] : ["context/#{file.path} doesn't match the diff at line #{bad.first.new_lineno}"]
        end
      end
    end

    module Dataset
      module_function

      def load(cases_dir)
        Dir[File.join(cases_dir, "*")].select { |d| File.directory?(d) }.sort.map { |d| Case.load(d) }
      end

      # Hash of every file under the cases directory, so a result can name
      # exactly which version of the dataset it was measured on.
      def version(cases_dir)
        digest = Digest::SHA256.new
        Dir.glob("**/*", File::FNM_DOTMATCH, base: cases_dir).sort.each do |rel|
          next if File.basename(rel) == "." || File.basename(rel) == ".."
          path = File.join(cases_dir, rel)
          next unless File.file?(path)

          digest << rel << "\0" << File.binread(path) << "\0"
        end
        digest.hexdigest[0, 16]
      end
    end
  end
end
