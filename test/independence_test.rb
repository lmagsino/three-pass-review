# frozen_string_literal: true

require "test_helper"

# The core design rule (ADR 0001): in independent mode no pass sees another
# pass's output or prompt. If this test fails, the design is broken.
class IndependenceTest < Minitest::Test
  BASIC = File.join(FIXTURES, "llm", "basic")
  PASSES = %w[correctness security architecture].freeze

  def setup
    @client = ThreePassReview::LLM::FakeClient.new(BASIC)
    @runner = ThreePassReview::Runner.new(client: @client, model: "claude-sonnet-5-5")
    @result = @runner.run(base_input)
    @requests = @client.requests.to_h { |r| [r.pass, r] }
  end

  def outputs_of(pass)
    JSON.parse(File.read(File.join(BASIC, "#{pass}.json")))["findings"].flat_map do |f|
      [f["title"], f["explanation"], f["suggested_fix"]]
    end
  end

  def test_no_request_contains_another_pass_output
    PASSES.each do |pass|
      sent = @requests.fetch(pass).system + @requests.fetch(pass).user
      (PASSES - [pass]).each do |other|
        outputs_of(other).each do |text|
          refute_includes sent, text, "#{pass} request contains #{other}'s output"
        end
      end
    end
  end

  def test_no_request_contains_another_pass_prompt
    PASSES.each do |pass|
      sent = @requests.fetch(pass).system + @requests.fetch(pass).user
      (PASSES - [pass]).each do |other|
        refute_includes sent, ThreePassReview::Prompts.read(other), "#{pass} request contains #{other}'s prompt"
      end
      refute_includes sent, ThreePassReview::Prompts.read("combined")
    end
  end

  def test_each_request_is_its_own_prompt_plus_the_shared_base_input
    PASSES.each do |pass|
      expected = "#{ThreePassReview::Prompts.read("shared")}\n\n#{ThreePassReview::Prompts.read(pass)}"
      assert_equal expected, @requests.fetch(pass).system
      refute_includes @requests.fetch(pass).user, "earlier_findings"
    end
    assert_equal @requests["correctness"].user, @requests["security"].user
  end

  def test_only_the_architecture_pass_gets_conventions
    assert_includes @requests["architecture"].user, "Money.format"
    refute_includes @requests["correctness"].user, "conventions_files"
  end

  def test_requests_are_identical_whatever_the_other_passes_return
    other = ThreePassReview::LLM::FakeClient.new(nil, responses: {
      "correctness" => {"findings" => []}, "security" => {"findings" => []}, "architecture" => {"findings" => []}
    })
    ThreePassReview::Runner.new(client: other, model: "claude-sonnet-5-5").run(base_input)

    other.requests.each { |req| assert_equal @requests.fetch(req.pass), req }
  end

  def test_untrusted_content_cannot_forge_an_end_marker
    user = @requests["security"].user
    id = user[/<<<BEGIN diff (\h{32})>>>/, 1]

    refute_nil id
    assert_equal 1, user.scan("<<<END diff #{id}>>>").size
  end

  def test_the_brief_and_the_checks_never_see_each_other
    client = ThreePassReview::LLM::FakeClient.new(BASIC)
    ThreePassReview::Runner.new(client: client, model: "claude-sonnet-5-5")
      .run(base_input, passes: PASSES + ["brief"])
    requests = client.requests.to_h { |r| [r.pass, r] }
    brief = requests.fetch("brief")
    brief_text = JSON.parse(File.read(File.join(BASIC, "brief.json")))["summary"]

    assert_equal ThreePassReview::Prompts.read("brief"), brief.system
    PASSES.each do |pass|
      outputs_of(pass).each { |text| refute_includes brief.user, text }
      refute_includes brief.system + brief.user, ThreePassReview::Prompts.read(pass)
      refute_includes requests.fetch(pass).system + requests.fetch(pass).user, ThreePassReview::Prompts.read("brief")
      refute_includes requests.fetch(pass).user, brief_text
      assert_equal @requests.fetch(pass), requests.fetch(pass), "adding the brief changed the #{pass} request"
    end
  end
end
