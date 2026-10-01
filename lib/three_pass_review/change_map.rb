# frozen_string_literal: true

module ThreePassReview
  # A high-level map of a diff, computed without a model: which areas it
  # touches, how much, and the kinds of change a deep reviewer should know
  # about (migrations, dependencies, tests, CI, deletions). Exact and free,
  # so it can sit at the top of a reviewer brief without any caveat.
  class ChangeMap
    Area = Data.define(:name, :files, :added, :removed, :flags)

    FLAGS = {
      "migration" => [%r{(\A|/)db/migrate/}, %r{(\A|/)migrations?/}, %r{(\A|/)alembic/versions/}, /\.sql\z/],
      "dependencies" => [
        %r{(\A|/)(Gemfile|Gemfile\.lock|package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum)\z},
        %r{(\A|/)(requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|uv\.lock|Cargo\.toml|Cargo\.lock|pom\.xml|build\.gradle[^/]*)\z}
      ],
      "tests" => [%r{(\A|/)(test|tests|spec|__tests__)/}, /[._-](test|spec)\.[a-z]+\z/, %r{(\A|/)test_[^/]+\.py\z}],
      "ci" => [%r{\A\.github/workflows/}, %r{\A\.gitlab-ci\.yml\z}, %r{\A\.circleci/}],
      "infra" => [/\.tf\z/, %r{(\A|/)Dockerfile[^/]*\z}, %r{(\A|/)(k8s|helm|terraform)/}],
      "docs" => [/\.(md|rst|adoc)\z/]
    }.freeze

    attr_reader :areas

    def self.build(diff)
      new(diff)
    end

    def initialize(diff)
      groups = diff.files.group_by { |f| area_of(f.path) }
      @areas = groups.map do |name, files|
        Area.new(
          name: name,
          files: files.size,
          added: files.sum { |f| count(f, :add) },
          removed: files.sum { |f| count(f, :del) },
          flags: files.flat_map { |f| flags_for(f) }.uniq.sort
        )
      end.sort_by { |a| [-(a.added + a.removed), a.name] }
      ThreePassReview.deep_freeze(@areas)
      freeze
    end

    def totals
      {files: areas.sum(&:files), added: areas.sum(&:added), removed: areas.sum(&:removed)}
    end

    def flags
      areas.flat_map(&:flags).uniq.sort
    end

    def to_h
      {"areas" => areas.map { |a| a.to_h.transform_keys(&:to_s) }, "totals" => totals.transform_keys(&:to_s)}
    end

    private

    # The folder two levels down for the usual source roots, so app/models and
    # app/controllers show as separate areas; one level everywhere else.
    def area_of(path)
      parts = path.split("/")
      return "(root)" if parts.size == 1

      depth = (%w[app src lib pkg internal packages services].include?(parts.first) && parts.size > 2) ? 2 : 1
      parts.first(depth).join("/")
    end

    def count(file, type)
      file.hunks.sum { |h| h.lines.count { |l| l.type == type } }
    end

    def flags_for(file)
      found = FLAGS.select { |_, patterns| patterns.any? { |re| re.match?(file.path) } }.keys
      found << "deleted" if file.deleted?
      found << "new" if file.status == :added
      found << "renamed" if file.status == :renamed
      found << "binary" if file.binary?
      found
    end
  end
end
