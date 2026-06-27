# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "net/http"

require_relative "../lib/flightwatch/data"

class TestTokenManager < Minitest::Test
  class FakeHTTP
    attr_reader :requests

    def initialize
      @requests = []
    end

    def start(_hostname, _port, use_ssl:)
      @use_ssl = use_ssl
      yield self
    end

    def request(request)
      @requests << request
      response = Net::HTTPOK.new("1.1", "200", "OK")
      body = JSON.generate("access_token" => "token-#{@requests.length}", "expires_in" => 1_800)
      response.instance_variable_set(:@read, true)
      response.body = body
      response
    end
  end

  def test_fetches_and_caches_bearer_token_until_refresh_window
    now = Time.at(1_000)
    clock = -> { now }
    http = FakeHTTP.new
    credentials = FlightWatch::Data::Credentials.new(client_id: "id", client_secret: "secret")
    manager = FlightWatch::Data::TokenManager.new(credentials: credentials, http: http, clock: clock)

    assert_equal "token-1", manager.bearer_token
    assert_equal "token-1", manager.bearer_token
    assert_equal 1, http.requests.length

    now = Time.at(2_700)
    assert_equal "token-2", manager.bearer_token
    assert_equal 2, http.requests.length
  end

  def test_posts_oauth_client_credentials_form
    http = FakeHTTP.new
    credentials = FlightWatch::Data::Credentials.new(client_id: "id", client_secret: "secret")
    manager = FlightWatch::Data::TokenManager.new(credentials: credentials, http: http, clock: -> { Time.at(1_000) })

    manager.bearer_token

    request = http.requests.first
    assert_equal "POST", request.method
    assert_includes request.body, "grant_type=client_credentials"
    assert_includes request.body, "client_id=id"
    assert_includes request.body, "client_secret=secret"
  end
end
