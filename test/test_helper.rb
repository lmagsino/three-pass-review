# frozen_string_literal: true

require "minitest/autorun"
require "socket"
require "three_pass_review"
require "three_pass_review/cli"

FIXTURES = File.expand_path("fixtures", __dir__)

# No network in tests: any attempt to open a socket fails the test loudly.
ENV.delete("ANTHROPIC_API_KEY")
module NoNetwork
  def self.refuse(*args)
    raise "network access attempted in a test: #{args.first(2).inspect}"
  end
end
TCPSocket.singleton_class.prepend(Module.new do
  def new(*args, **) = NoNetwork.refuse(*args)

  def open(*args, **) = NoNetwork.refuse(*args)
end)
Socket.singleton_class.prepend(Module.new do
  def tcp(*args, **) = NoNetwork.refuse(*args)
end)

module TestSupport
  def fixture_diff(name = "basic.patch")
    ThreePassReview::Diff.parse(File.read(File.join(FIXTURES, "diffs", name)))
  end

  def base_input(diff_name = "basic.patch", **opts)
    ThreePassReview::ContextBuilder.new(repo: File.join(FIXTURES, "repo"), **opts)
      .build(diff: fixture_diff(diff_name), title: "Add sortable invoices", body: "Sort invoices by column.")
  end

  def finding_hash(**overrides)
    {
      "file" => "app/models/invoice.rb", "line_start" => 8, "line_end" => 8,
      "category" => "security", "subcategory" => "sql_injection", "severity" => "high",
      "confidence" => 0.9, "title" => "User input interpolated into SQL",
      "explanation" => "Unescaped.", "evidence" => "order(...)", "suggested_fix" => "Allow-list."
    }.merge(overrides.transform_keys(&:to_s))
  end
end
Minitest::Test.include(TestSupport)
