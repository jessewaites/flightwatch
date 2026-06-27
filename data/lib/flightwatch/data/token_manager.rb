# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module FlightWatch
  module Data
    class TokenManager
      TOKEN_ENDPOINT = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
      REFRESH_SKEW_SECONDS = 120

      def initialize(credentials: Credentials.load, endpoint: TOKEN_ENDPOINT, http: Net::HTTP, clock: -> { Time.now })
        @credentials = credentials
        @endpoint = URI(endpoint)
        @http = http
        @clock = clock
        @access_token = nil
        @expires_at = Time.at(0)
      end

      def bearer_token
        refresh! if refresh_needed?
        @access_token
      end

      def refresh!
        raise "OpenSky credentials missing: set OPENSKY_CLIENT_ID and OPENSKY_CLIENT_SECRET or credentials.json" unless @credentials.complete?

        request = Net::HTTP::Post.new(@endpoint)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.set_form_data(
          "grant_type" => "client_credentials",
          "client_id" => @credentials.client_id,
          "client_secret" => @credentials.client_secret
        )

        response = @http.start(@endpoint.hostname, @endpoint.port, use_ssl: @endpoint.scheme == "https") do |connection|
          connection.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise "OpenSky token request failed: HTTP #{response.code} #{response.message}"
        end

        body = JSON.parse(response.body)
        token = body.fetch("access_token")
        expires_in = Integer(body.fetch("expires_in", 1800))

        @access_token = token
        @expires_at = @clock.call + expires_in
        @access_token
      end

      private

      def refresh_needed?
        @access_token.nil? || (@clock.call + REFRESH_SKEW_SECONDS) >= @expires_at
      end
    end
  end
end
