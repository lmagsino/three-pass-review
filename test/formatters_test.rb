# frozen_string_literal: true

require "test_helper"

class FormattersTest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")
  GOLDEN = File.join(FIXTURES, "golden")

  def outcome(responses: nil, config: {}, diff: fixture_diff.text, mode: "independent")
    client = responses ? ThreePassReview::LLM::FakeClient.new(nil, responses: responses) : ThreePassReview::LLM::FakeClient.new(BASIC)
    ThreePassReview::Review.new(config: ThreePassReview::Config.new(config), client: client, repo: File.join(FIXTURES, "repo"))
      .run(diff_text: diff, title: "Add sortable invoices", body: "Sort invoices by column.", mode: mode)
  end

  # Prompt hashes are part of the output, so the golden files pin them as a
  # placeholder; set UPDATE_GOLDEN=1 to rewrite after an intended change.
  def assert_golden(name, actual)
    actual = actual.gsub(ThreePassReview::Prompts.version, "PROMPTS_VERSION").gsub(/sha256:\h{64}/, "sha256:HASH")
    path = File.join(GOLDEN, name)
    File.write(path, actual) if ENV["UPDATE_GOLDEN"]
    assert_equal File.read(path), actual
  end

  def test_markdown_golden
    assert_golden("basic.md", ThreePassReview::Formatters::Markdown.new(outcome).render)
  end

  def test_json_golden
    assert_golden("basic.json", ThreePassReview::Formatters::JSON.new(outcome).render)
  end

  def test_markdown_starts_with_the_marker
    assert ThreePassReview::Formatters::Markdown.new(outcome).render.start_with?("<!-- threepass -->\n")
  end

  def test_no_findings_and_empty_diff_headings
    quiet = {"correctness" => {"findings" => []}, "security" => {"findings" => []}, "architecture" => {"findings" => []}}

    assert_includes ThreePassReview::Formatters::Markdown.new(outcome(responses: quiet)).render, "### threepass: no findings"
    assert_includes ThreePassReview::Formatters::Markdown.new(outcome(diff: "")).render, "### threepass: nothing to review"
  end

  def test_failed_passes_and_degradations_are_reported
    responses = {
      "correctness" => {"findings" => []}, "architecture" => {"findings" => []},
      "security" => {"error" => "output cut off at max_output_tokens (4000); raise it", "usage" => {"input_tokens" => 10, "output_tokens" => 4000}}
    }
    md = ThreePassReview::Formatters::Markdown.new(outcome(responses: responses, config: {"max_cost_usd" => 0.13})).render

    assert_includes md, "> ⚠️ The security pass failed, so its findings are missing: output cut off"
    assert_match(/> To stay under the \$0\.130 cost ceiling: file excerpts shrunk/, md)
  end

  def test_untrusted_text_cannot_inject_markup_mentions_or_break_the_table
    evil = finding_hash(title: "Bad | <img src=x> @octocat", explanation: "<!-- threepass --> ping @admin",
      evidence: "x = ```danger```", suggested_fix: "<script>")
    md = ThreePassReview::Formatters::Markdown.new(outcome(responses: {
      "security" => {"findings" => [evil]}, "correctness" => {"findings" => []}, "architecture" => {"findings" => []}
    })).render

    assert_equal 1, md.scan("<!-- threepass -->").size
    refute_includes md, "<img"
    refute_includes md, "<script>"
    refute_match(/@octocat|@admin/, md)
    assert_includes md, "Bad \\| &lt;img src=x&gt;"
    assert_includes md, "````\nx = ```danger```\n````"
  end

  def test_untrusted_text_cannot_change_the_comment_structure
    evil = finding_hash(explanation: "```\n# Fake heading\nsee #123 and [x](https://evil) ![i](https://evil/p.png)",
      suggested_fix: "~~~")
    md = ThreePassReview::Formatters::Markdown.new(outcome(responses: {
      "security" => {"findings" => [evil]}, "correctness" => {"findings" => []}, "architecture" => {"findings" => []}
    })).render
    details = md[/<details>.*<\/details>/m]

    assert_includes details, "\\`\\`\\`\n\\# Fake heading"
    assert_includes details, "##{ThreePassReview::Formatters::Text::ZERO_WIDTH_SPACE}123"
    assert_includes details, "\\[x\\](https://evil)"
    assert_includes details, "**Suggested fix:** \\~\\~\\~"
    assert md.end_with?("</sub>\n")
  end

  def test_json_reports_passes_counts_and_cost
    data = JSON.parse(ThreePassReview::Formatters::JSON.new(outcome).render)

    assert_equal %w[correctness security architecture], data["passes"].map { |p| p["pass"] }
    assert_equal %w[ok ok ok], data["passes"].map { |p| p["status"] }
    assert_equal 3, data["passes"].first["raw_findings"].size
    assert_operator data["cost"]["total_usd"], :<=, data["cost"]["max_cost_usd"]
    assert_equal ThreePassReview::Prompts.hashes, data["prompts"]["hashes"]
  end
end
