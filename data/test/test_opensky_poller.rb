# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "net/http"

require_relative "../lib/flightwatch/data"

class TestOpenSkyPoller < Minitest::Test
  class FakeHTTP
    attr_reader :request_seen, :use_ssl_seen

    def start(_hostname, _port, use_ssl:)
      @use_ssl_seen = use_ssl
      yield self
    end

    def request(request)
      @request_seen = request
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate("time" => 1_782_145_125, "states" => [])
      response
    end
  end

  FakeTokenManager = Struct.new(:bearer_token)

  def test_polls_opensky_states_with_boston_bbox_and_bearer_token
    http = FakeHTTP.new
    poller = FlightWatch::Data::OpenSkyPoller.new(
      token_manager: FakeTokenManager.new("abc123"),
      http: http
    )

    raw = poller.poll_raw

    assert_equal 1_782_145_125, raw.fetch("time")
    assert_equal true, http.use_ssl_seen
    assert_equal "Bearer abc123", http.request_seen["Authorization"]

    params = URI.decode_www_form(http.request_seen.uri.query).to_h
    assert_equal "42.2", params.fetch("lamin")
    assert_equal "-71.2", params.fetch("lomin")
    assert_equal "42.5", params.fetch("lamax")
    assert_equal "-70.9", params.fetch("lomax")
  end
end
