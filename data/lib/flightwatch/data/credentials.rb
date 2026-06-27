# frozen_string_literal: true

require "json"

module FlightWatch
  module Data
    class Credentials
      DEFAULT_ENV_PATH = File.expand_path("../../../../.env", __dir__)
      DEFAULT_JSON_PATH = File.expand_path("../../../../credentials.json", __dir__)

      attr_reader :client_id, :client_secret

      def self.load(env_path: DEFAULT_ENV_PATH, json_path: DEFAULT_JSON_PATH, env: ENV)
        new(
          client_id: env["OPENSKY_CLIENT_ID"] || env["client_id"],
          client_secret: env["OPENSKY_CLIENT_SECRET"] || env["client_secret"]
        ).merge_dotenv(env_path).merge_json(json_path)
      end

      def initialize(client_id: nil, client_secret: nil)
        @client_id = blank_to_nil(client_id)
        @client_secret = blank_to_nil(client_secret)
      end

      def complete?
        !client_id.nil? && !client_secret.nil?
      end

      def merge_dotenv(path)
        return self unless File.file?(path)

        File.readlines(path, chomp: true).each do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          key, value = stripped.split("=", 2)
          next unless key && value

          assign(key.strip, clean_value(value.strip))
        end
        self
      end

      def merge_json(path)
        return self unless File.file?(path)

        parsed = JSON.parse(File.read(path))
        assign_from_hash(parsed)
        self
      rescue JSON::ParserError
        self
      end

      private

      def assign_from_hash(hash)
        return unless hash.is_a?(Hash)

        assign("client_id", hash["client_id"] || hash["opensky_client_id"] || hash["OPENSKY_CLIENT_ID"])
        assign("client_secret", hash["client_secret"] || hash["opensky_client_secret"] || hash["OPENSKY_CLIENT_SECRET"])
        assign_from_hash(hash["opensky"]) if hash["opensky"].is_a?(Hash)
      end

      def assign(key, value)
        normalized_key = key.to_s.downcase
        cleaned = blank_to_nil(value)
        return if cleaned.nil?

        case normalized_key
        when "client_id", "opensky_client_id"
          @client_id ||= cleaned
        when "client_secret", "opensky_client_secret"
          @client_secret ||= cleaned
        end
      end

      def clean_value(value)
        value.sub(/\A["']/, "").sub(/["']\z/, "")
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
