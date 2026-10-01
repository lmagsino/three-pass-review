# frozen_string_literal: true

require "yaml"

module ThreePassReview
  # Defaults from defaults.yml, overridden by .threepass.yml, then validated.
  class Config
    class Invalid < Error; end

    DEFAULTS_PATH = File.expand_path("defaults.yml", __dir__)
    FILE_NAME = ".threepass.yml"
    EFFORTS = %w[low medium high xhigh max].freeze

    def self.defaults
      YAML.safe_load_file(DEFAULTS_PATH)
    end

    def self.load(path = nil)
      overrides = {}
      if path
        raise Invalid, "config file not found: #{path}" unless File.file?(path)

        overrides = YAML.safe_load_file(path) || {}
        raise Invalid, "#{path} must be a YAML mapping" unless overrides.is_a?(Hash)
      end
      new(overrides)
    rescue Psych::Exception => e
      raise Invalid, "#{path}: #{e.message}"
    end

    attr_reader :data

    def initialize(overrides = {})
      defaults = self.class.defaults
      check_keys(overrides, defaults, [])
      @data = ThreePassReview.deep_freeze(merge(defaults, overrides))
      validate!
    end

    def model = data["model"]
    def max_cost_usd = data["max_cost_usd"].to_f
    def max_output_tokens = data["max_output_tokens"]
    def effort = data["effort"]
    def confidence_threshold = data["confidence_threshold"].to_f
    def max_comments = data["max_comments"]
    def merge_line_gap = data["merge_line_gap"]
    def samples = data["samples"]
    def lines_around_hunk = data.dig("context", "lines_around_hunk")
    def reduced_lines_around_hunk = data.dig("context", "reduced_lines_around_hunk")
    def max_excerpt_bytes = data.dig("context", "max_excerpt_bytes")
    def max_conventions_bytes = data.dig("context", "max_conventions_bytes")
    def conventions = data.dig("passes", "architecture", "conventions")

    def enabled_passes
      Runner::PASS_ORDER.select { |name| data.dig("passes", name, "enabled") }
    end

    # {input:, output:} in USD per million tokens, or nil when not configured.
    def pricing_for(model_id = model)
      entry = data.dig("pricing", model_id)
      return nil unless entry && entry["input"] && entry["output"]

      {input: entry["input"].to_f, output: entry["output"].to_f}
    end

    private

    def merge(base, over)
      base.merge(over) { |_key, a, b| (a.is_a?(Hash) && b.is_a?(Hash)) ? merge(a, b) : b }
    end

    # A typo would otherwise silently fall back to a default. Pricing and
    # passes are the only maps whose keys aren't fixed.
    def check_keys(over, base, path)
      over.each do |key, value|
        where = (path + [key]).join(".")
        open_map = path == ["pricing"] || path == ["passes"]
        known = base.is_a?(Hash) && (base.key?(key) || open_map)
        raise Invalid, "unknown config key #{where}" unless known

        expects_map = base[key].is_a?(Hash) || (open_map && path == ["passes"])
        raise Invalid, "#{where} must be a mapping" if expects_map && !value.is_a?(Hash)

        check_keys(value, base[key], path + [key]) if value.is_a?(Hash) && base[key].is_a?(Hash) && path != ["pricing"]
      end
    end

    def validate!
      problems = []
      problems << "model must be a string" if !model.is_a?(String) || model.empty?
      problems << "max_cost_usd must be a positive number" unless data["max_cost_usd"].is_a?(Numeric) && max_cost_usd.positive?
      %w[max_output_tokens max_comments samples].each do |key|
        problems << "#{key} must be a positive integer" unless data[key].is_a?(Integer) && data[key].positive?
      end
      problems << "merge_line_gap must be a non-negative integer" unless merge_line_gap.is_a?(Integer) && merge_line_gap >= 0
      unless data["confidence_threshold"].is_a?(Numeric) && confidence_threshold.between?(0, 1)
        problems << "confidence_threshold must be between 0 and 1"
      end
      problems << "effort must be one of #{EFFORTS.join(", ")} or null" unless effort.nil? || EFFORTS.include?(effort)
      %w[lines_around_hunk reduced_lines_around_hunk max_excerpt_bytes max_conventions_bytes].each do |key|
        value = data.dig("context", key)
        problems << "context.#{key} must be a non-negative integer" unless value.is_a?(Integer) && value >= 0
      end
      unknown = data["passes"].keys - Runner::PASS_ORDER
      problems << "unknown passes: #{unknown.join(", ")}" if unknown.any?
      problems << "at least one pass must be enabled" if enabled_passes.empty?
      data["passes"].each do |name, pass|
        problems << "passes.#{name}.enabled must be true or false" unless [true, false].include?(pass["enabled"])
      end
      plain_paths = conventions.is_a?(Array) && conventions.all? do |path|
        path.is_a?(String) && !path.empty? && !path.start_with?("/") && !path.split("/").include?("..")
      end
      problems << "passes.architecture.conventions must be a list of relative paths inside the repo" unless plain_paths
      data["pricing"].each do |id, rates|
        ok = rates.is_a?(Hash) && rates.slice("input", "output").values.all? { |v| v.nil? || (v.is_a?(Numeric) && v >= 0) }
        problems << "pricing.#{id} needs numeric input and output rates" unless ok
      end
      raise Invalid, problems.join("; ") if problems.any?
    end
  end
end
