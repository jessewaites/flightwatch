# frozen_string_literal: true

module FlightWatch
  module Data
    module Normalizer
      METERS_TO_FEET = 3.280_839_895
      METERS_PER_SECOND_TO_KNOTS = 1.943_844_492
      METERS_PER_SECOND_TO_FEET_PER_MINUTE = 196.850_394

      module_function

      def normalize(raw)
        {
          "ts" => integer(raw.fetch("time")),
          "aircraft" => Array(raw["states"]).map { |state| normalize_aircraft(state) }
        }
      end

      def normalize_aircraft(state)
        {
          "icao24" => string_or_nil(state[0]).to_s.downcase,
          "callsign" => callsign(state[1]),
          "lat" => number_or_nil(state[6]),
          "lon" => number_or_nil(state[5]),
          "baro_alt_ft" => meters_to_feet(state[7]),
          "velocity_kt" => meters_per_second_to_knots(state[9]),
          "heading" => number_or_nil(state[10]),
          "vert_rate_fpm" => meters_per_second_to_feet_per_minute(state[11]),
          "on_ground" => state[8] == true,
          "squawk" => string_or_nil(state[14]),
          "last_contact" => integer(state[4])
        }
      end

      def callsign(value)
        text = string_or_nil(value)
        text&.strip
      end

      def string_or_nil(value)
        return nil if value.nil?

        text = value.to_s
        text.empty? ? nil : text
      end

      def integer(value)
        Integer(value)
      end

      def number_or_nil(value)
        return nil if value.nil?

        Float(value)
      end

      def meters_to_feet(value)
        convert(value, METERS_TO_FEET)
      end

      def meters_per_second_to_knots(value)
        convert(value, METERS_PER_SECOND_TO_KNOTS)
      end

      def meters_per_second_to_feet_per_minute(value)
        convert(value, METERS_PER_SECOND_TO_FEET_PER_MINUTE)
      end

      def convert(value, multiplier)
        return nil if value.nil?

        rounded(Float(value) * multiplier)
      end

      def rounded(value)
        rounded = value.round(2)
        rounded == rounded.to_i ? rounded.to_i : rounded
      end
    end
  end
end
