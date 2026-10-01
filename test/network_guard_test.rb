# frozen_string_literal: true

require "test_helper"
require "net/http"

class NetworkGuardTest < Minitest::Test
  def test_sockets_are_refused
    assert_raises(RuntimeError) { TCPSocket.new("example.com", 443) }
    assert_raises(RuntimeError) { Socket.tcp("example.com", 443) }
  end

  def test_http_is_refused
    error = assert_raises(RuntimeError) { Net::HTTP.get(URI("https://api.anthropic.com/v1/models")) }
    assert_match(/network access attempted/, error.message)
  end
end
