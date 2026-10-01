# frozen_string_literal: true

module ThreePassReview
  Finding = Data.define(:file, :line_start, :line_end, :category, :subcategory, :severity, :confidence,
    :title, :explanation, :evidence, :suggested_fix, :pass)

  class Finding
    CATEGORIES = %w[correctness security architecture].freeze
    SEVERITIES = %w[critical high medium low].freeze
    STRING_FIELDS = %w[file category subcategory severity title explanation evidence suggested_fix].freeze
    FIELDS = (STRING_FIELDS + %w[line_start line_end confidence]).freeze
    # How far outside the changed hunks a cited line may sit and still be valid.
    LINE_MARGIN = 3

    class << self
      # JSON schema for structured output. Structured outputs reject numeric
      # bounds, so the 0..1 range of confidence is enforced in validate.
      def schema(categories)
        {
          type: "object",
          additionalProperties: false,
          required: ["findings"],
          properties: {
            findings: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: FIELDS,
                properties: {
                  file: {type: "string", description: "Path of a file in the diff, as the diff names it"},
                  line_start: {type: "integer", description: "First line of the problem, in the new version of the file"},
                  line_end: {type: "integer", description: "Last line of the problem, in the new version of the file"},
                  category: {type: "string", enum: categories},
                  subcategory: {type: "string", description: "Short snake_case kind, e.g. sql_injection, off_by_one"},
                  severity: {type: "string", enum: SEVERITIES},
                  confidence: {type: "number", description: "0 to 1: how sure you are this is a real problem"},
                  title: {type: "string"},
                  explanation: {type: "string"},
                  evidence: {type: "string", description: "The exact code, quoted from the input"},
                  suggested_fix: {type: "string"}
                }
              }
            }
          }
        }
      end

      # Returns [finding, nil] or [nil, reason].
      def validate(hash, diff:, pass:, margin: LINE_MARGIN)
        return [nil, "not an object"] unless hash.is_a?(Hash)

        missing = FIELDS.reject { |f| hash.key?(f) }
        return [nil, "missing #{missing.join(", ")}"] if missing.any?

        bad = STRING_FIELDS.reject { |f| hash[f].is_a?(String) }
        return [nil, "#{bad.join(", ")} not a string"] if bad.any?
        return [nil, "#{hash["category"]} is not a category"] unless CATEGORIES.include?(hash["category"])
        return [nil, "#{hash["severity"]} is not a severity"] unless SEVERITIES.include?(hash["severity"])

        line_start = hash["line_start"]
        line_end = hash["line_end"]
        unless line_start.is_a?(Integer) && line_end.is_a?(Integer) && line_start.positive? && line_end >= line_start
          return [nil, "invalid line range"]
        end

        confidence = hash["confidence"]
        return [nil, "confidence outside 0..1"] unless confidence.is_a?(Numeric) && confidence.between?(0, 1)

        file = diff.file(hash["file"])
        return [nil, "file not in diff"] if file.nil? || file.deleted?
        return [nil, "lines outside the changed hunks"] unless file.covers?(line_start, line_end, margin: margin)

        finding = new(
          file: hash["file"], line_start: line_start, line_end: line_end,
          category: hash["category"], subcategory: hash["subcategory"].strip.downcase,
          severity: hash["severity"], confidence: confidence.to_f,
          title: hash["title"].strip, explanation: hash["explanation"].strip,
          evidence: hash["evidence"], suggested_fix: hash["suggested_fix"].strip,
          pass: pass.to_s
        )
        [ThreePassReview.deep_freeze(finding), nil]
      end
    end

    def severity_rank
      SEVERITIES.index(severity)
    end

    def location
      (line_start == line_end) ? "#{file}:#{line_start}" : "#{file}:#{line_start}-#{line_end}"
    end
  end
end
