# frozen_string_literal: true

module ThreePassReview
  # The reviewer brief: a high-level account of a change for the person doing
  # the deep review. Written by its own call on the same frozen input as the
  # checks, so it never sees their findings.
  Brief = Data.define(:summary, :changes, :impact, :risks, :rollback, :tests_covered, :test_gaps,
    :review_order, :questions, :dropped_review_order)

  class Brief
    IMPACT_KINDS = %w[behavior api_contract data config dependency security performance].freeze
    MAX_ITEMS = 5
    STRING_LISTS = %w[risks tests_covered test_gaps questions].freeze

    class << self
      def schema
        string_list = {type: "array", items: {type: "string"}}
        object = ->(properties) { {type: "object", additionalProperties: false, required: properties.keys.map(&:to_s), properties: properties} }
        object.call(
          summary: {type: "string"},
          changes: {type: "array", items: object.call(area: {type: "string"}, description: {type: "string"})},
          impact: {type: "array", items: object.call(kind: {type: "string", enum: IMPACT_KINDS}, description: {type: "string"})},
          risks: string_list,
          rollback: {type: "string"},
          tests_covered: string_list,
          test_gaps: string_list,
          review_order: {
            type: "array",
            items: object.call(
              file: {type: "string", description: "Path of a file in the diff"},
              line_start: {type: "integer", description: "First line, in the new version of the file"},
              line_end: {type: "integer", description: "Last line, in the new version of the file"},
              why: {type: "string"}
            )
          },
          questions: string_list
        )
      end

      # Returns [brief, nil] or [nil, reason]. A review_order entry that
      # doesn't point inside the diff is dropped and counted, like an invalid
      # finding; the rest of the brief is kept.
      def from(data, diff:, margin: Finding::LINE_MARGIN)
        return [nil, "reply was not an object"] unless data.is_a?(Hash)
        return [nil, "summary missing"] unless data["summary"].is_a?(String) && !data["summary"].strip.empty?

        order = list(data["review_order"]).select { |e| e.is_a?(Hash) }
        valid_order = order.select { |e| points_into_diff?(e, diff, margin) }.first(MAX_ITEMS)
        brief = new(
          summary: data["summary"].strip,
          changes: pairs(data["changes"], "area", "description"),
          impact: pairs(data["impact"], "kind", "description").select { |i| IMPACT_KINDS.include?(i["kind"]) },
          risks: strings(data["risks"]),
          rollback: data["rollback"].to_s.strip,
          tests_covered: strings(data["tests_covered"]),
          test_gaps: strings(data["test_gaps"]),
          review_order: valid_order.map { |e| e.slice("file", "line_start", "line_end", "why").merge("why" => e["why"].to_s.strip) },
          questions: strings(data["questions"]).first(MAX_ITEMS),
          dropped_review_order: order.size - order.count { |e| points_into_diff?(e, diff, margin) }
        )
        [ThreePassReview.deep_freeze(brief), nil]
      end

      private

      def list(value)
        value.is_a?(Array) ? value : []
      end

      def strings(value)
        list(value).select { |s| s.is_a?(String) }.map(&:strip).reject(&:empty?)
      end

      def pairs(value, *keys)
        list(value).select { |e| e.is_a?(Hash) && keys.all? { |k| e[k].is_a?(String) } }.map { |e| e.slice(*keys) }
      end

      def points_into_diff?(entry, diff, margin)
        file = diff.file(entry["file"].to_s)
        start = entry["line_start"]
        finish = entry["line_end"]
        return false unless file && !file.deleted? && start.is_a?(Integer) && finish.is_a?(Integer)
        return false unless start.positive? && finish >= start

        file.covers?(start, finish, margin: margin)
      end
    end
  end
end
