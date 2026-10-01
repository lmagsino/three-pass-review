# frozen_string_literal: true

module ThreePassReview
  module Eval
    module Metrics
      Z95 = 1.959964

      module_function

      # Wilson score interval for k successes out of n; nil when n is zero.
      def wilson(k, n, z: Z95)
        return nil if n.zero?

        p = k.to_f / n
        denom = 1 + z**2 / n
        center = (p + z**2 / (2 * n)) / denom
        half = z * Math.sqrt(p * (1 - p) / n + z**2 / (4.0 * n**2)) / denom
        [[center - half, 0.0].max, [center + half, 1.0].min]
      end

      # Linear interpolation between closest ranks; nil for no values.
      def percentile(values, pct)
        sorted = values.compact.sort
        return nil if sorted.empty?

        rank = (pct / 100.0) * (sorted.size - 1)
        low = sorted[rank.floor]
        high = sorted[rank.ceil]
        low + (high - low) * (rank - rank.floor)
      end

      def proportion(k, n)
        {"k" => k, "n" => n, "rate" => n.zero? ? nil : k.to_f / n, "ci95" => wilson(k, n)}
      end
    end
  end
end
