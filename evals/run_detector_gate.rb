#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/flightwatch_eval"

module FlightWatch
  module Eval
    class DetectorGate
      CLEAN_ID = "clean001"

      def initialize(detector_mode)
        @detector_mode = detector_mode
        @detector = DetectorAdapter.load(detector_mode)
      end

      def run
        cases = [
          emergency_squawk_case,
          rapid_descent_case,
          going_dark_case,
          holding_pattern_case
        ].map { |test_case| run_case(test_case) }
        {
          "status" => cases.all? { |test_case| test_case.fetch("pass") } ? "PASS" : "FAIL",
          "detector_mode" => resolved_mode,
          "cases" => cases
        }
      end

      private

      def resolved_mode
        return @detector_mode unless @detector_mode == "auto"

        path = File.join(ROOT, "skills", "flight-anomaly-rules", "scripts", "detect.rb")
        File.exist?(path) ? "repo" : "reference"
      end

      def run_case(test_case)
        buffer = []
        flags_by_frame = []
        test_case.fetch("frames").each_with_index do |frame, index|
          Eval.validate_contract!(:frame, frame)
          flags = @detector.call(frame, buffer)
          flags.each { |flag| Eval.validate_contract!(:flag, flag) }
          flags_by_frame << { "frame_index" => index, "ts" => frame.fetch("ts"), "flags" => flags }
          buffer << frame
        end

        expected = test_case.fetch("expected")
        matches = flags_by_frame.flat_map do |row|
          row.fetch("flags").select do |flag|
            row.fetch("frame_index") >= expected.fetch("plant_frame") &&
              flag["icao24"] == expected.fetch("icao24") &&
              flag["rule"] == expected.fetch("rule")
          end.map { |flag| row.merge("flag" => flag) }
        end
        pre_fires = flags_by_frame.flat_map do |row|
          row.fetch("flags").select do |flag|
            row.fetch("frame_index") < expected.fetch("plant_frame") &&
              flag["icao24"] == expected.fetch("icao24") &&
              flag["rule"] == expected.fetch("rule")
          end
        end
        clean_false_flags = flags_by_frame.flat_map do |row|
          row.fetch("flags").select { |flag| flag["icao24"] == CLEAN_ID }
        end

        passed = !matches.empty? && pre_fires.empty? && clean_false_flags.empty?
        {
          "id" => test_case.fetch("id"),
          "input" => {
            "target_icao24" => expected.fetch("icao24"),
            "rule" => expected.fetch("rule"),
            "plant_frame" => expected.fetch("plant_frame")
          },
          "assertion" => "strict rule+aircraft match at or after plant frame, no pre-fire, no clean-aircraft flags",
          "pass" => passed,
          "evidence" => {
            "first_match_frame" => matches.empty? ? nil : matches.first.fetch("frame_index"),
            "match_count" => matches.length,
            "pre_fire_count" => pre_fires.length,
            "clean_false_flag_count" => clean_false_flags.length,
            "total_flags" => flags_by_frame.map { |row| row.fetch("flags").length }.inject(0, :+)
          }
        }
      end

      def emergency_squawk_case
        target = base_aircraft("target7700")
        frames = [
          frame_at(1000, [target, clean_aircraft]),
          frame_at(1010, [target.merge("squawk" => "7700"), clean_aircraft(1010)])
        ]
        case_hash("emergency-squawk-7700", frames, target.fetch("icao24"), "emergency_squawk", 1)
      end

      def rapid_descent_case
        target = base_aircraft("targetrd")
        frames = [
          frame_at(2000, [target, clean_aircraft(2000)]),
          frame_at(2010, [target.merge("vert_rate_fpm" => -3200), clean_aircraft(2010)])
        ]
        case_hash("rapid-descent", frames, target.fetch("icao24"), "rapid_descent", 1)
      end

      def going_dark_case
        target = base_aircraft("targetdark")
        frames = [
          frame_at(3000, [target.merge("last_contact" => 3000), clean_aircraft(3000)]),
          frame_at(3010, [target.merge("last_contact" => 3010), clean_aircraft(3010)]),
          frame_at(3260, [target.merge("last_contact" => 2950), clean_aircraft(3260)])
        ]
        case_hash("going-dark-staleness", frames, target.fetch("icao24"), "going_dark", 2)
      end

      def holding_pattern_case
        headings = [350, 20, 60, 100, 140, 180, 220, 260, 300]
        frames = headings.each_with_index.map do |heading, index|
          angle = index * 40.0 * Math::PI / 180.0
          target = base_aircraft("targethold", 4000 + index * 10).merge(
            "lat" => 42.36 + Math.sin(angle) * 0.012,
            "lon" => -71.02 + Math.cos(angle) * 0.012,
            "heading" => heading
          )
          frame_at(4000 + index * 10, [target, clean_aircraft(4000 + index * 10)])
        end
        case_hash("holding-pattern-heading-wrap", frames, "targethold", "holding_pattern", 6)
      end

      def case_hash(id, frames, icao24, rule, plant_frame)
        {
          "id" => id,
          "frames" => frames,
          "expected" => {
            "icao24" => icao24,
            "rule" => rule,
            "plant_frame" => plant_frame
          }
        }
      end

      def frame_at(ts, aircraft)
        { "ts" => ts, "aircraft" => aircraft }
      end

      def base_aircraft(icao24, ts = 1000)
        {
          "icao24" => icao24,
          "callsign" => icao24.upcase,
          "lat" => 42.35,
          "lon" => -71.01,
          "baro_alt_ft" => 5000,
          "velocity_kt" => 210,
          "heading" => 90,
          "vert_rate_fpm" => 0,
          "on_ground" => false,
          "squawk" => "1200",
          "last_contact" => ts
        }
      end

      def clean_aircraft(ts = 1000)
        base_aircraft(CLEAN_ID, ts).merge(
          "lat" => 42.42,
          "lon" => -70.98,
          "heading" => 45,
          "baro_alt_ft" => 6500,
          "velocity_kt" => 180
        )
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  mode = ENV.fetch("DETECT_IMPL", "auto")
  result = FlightWatch::Eval::DetectorGate.new(mode).run
  FlightWatch::Eval.write_json(File.join(__dir__, "detector_results.json"), result)
  puts JSON.pretty_generate(result)
  exit(result.fetch("status") == "PASS" ? 0 : 1)
end
