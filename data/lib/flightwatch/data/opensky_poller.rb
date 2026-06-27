# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module FlightWatch
  module Data
    class OpenSkyPoller
      STATES_ENDPOINT = "https://opensky-network.org/api/states/all"
      BOSTON_BBOX = {
        "lamin" => 42.2,
        "lomin" => -71.2,
        "lamax" => 42.5,
        "lomax" => -70.9
      }.freeze

      def initialize(token_manager: nil, endpoint: STATES_ENDPOINT, bbox: BOSTON_BBOX, http: Net::HTTP)
        @token_manager = token_manager
        @endpoint = URI(endpoint)
        @bbox = bbox
        @http = http
      end

      def poll_raw
        uri = @endpoint.dup
        uri.query = URI.encode_www_form(@bbox)
        request = Net::HTTP::Get.new(uri)

        token = @token_manager&.bearer_token
        request["Authorization"] = "Bearer #{token}" if token

        response = @http.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |connection|
          connection.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise "OpenSky states request failed: HTTP #{response.code} #{response.message}"
        end

        JSON.parse(response.body)
      end

      def next_frame
        Normalizer.normalize(poll_raw)
      end
    end
  end
end
