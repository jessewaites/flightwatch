# frozen_string_literal: true

require "json"
require "minitest/autorun"

ROOT = File.expand_path("../../..", __dir__)
require File.join(ROOT, "contracts/validate")
load File.join(ROOT, "skills/flight-anomaly-rules/scripts/detect.rb")

class DetectTest < Minitest::Test
  def test_fixture_plus_buffer_flags_expected_airborne_planes_only
    frame = JSON.parse(File.read(File.join(ROOT, "contracts/fixtures/frame.sample.json")))
    buffer = holding_buffer_for(frame.fetch("ts"))

    flags = detect(frame, buffer)
    by_id = flags.each_with_object({}) { |flag, memo| memo[flag.fetch("icao24")] = flag }

    assert_equal %w[a35e3d a37c1c a4996b], flags.map { |flag| flag.fetch("icao24") }.sort
    assert_equal "emergency_squawk", by_id.fetch("a35e3d").fetch("rule")
    assert_equal "holding_pattern", by_id.fetch("a4996b").fetch("rule")
    assert_equal "going_dark", by_id.fetch("a37c1c").fetch("rule")
    refute_includes flags.map { |flag| flag.fetch("icao24") }, "a3689e"
    refute_includes flags.map { |flag| flag.fetch("icao24") }, "5003bc"

    flags.each do |flag|
      ok, errors = FlightWatch::Contracts.validate(:flag, flag)
      assert ok, errors.join(", ")
    end
  end

  def test_planted_7700_on_ground_is_filtered
    frame = {
      "ts" => 1782145700,
      "aircraft" => [
        aircraft("ground1", on_ground: true, squawk: "7700", lat: 42.36, lon: -71.01),
        aircraft("air1", squawk: "7700", lat: 42.37, lon: -71.02)
      ]
    }

    flags = detect(frame, [])

    assert_equal ["air1"], flags.map { |flag| flag.fetch("icao24") }
    assert_equal "emergency_squawk", flags.first.fetch("rule")
  end

  def test_rapid_descent_without_emergency_squawk
    frame = {
      "ts" => 1782145700,
      "aircraft" => [
        aircraft("drop1", vert_rate_fpm: -2600, lat: 42.37, lon: -71.02)
      ]
    }

    flags = detect(frame, [])

    assert_equal 1, flags.length
    assert_equal "rapid_descent", flags.first.fetch("rule")
  end

  def test_holding_pattern_handles_heading_wraparound
    ts = 1782145700
    frame = {
      "ts" => ts,
      "aircraft" => [
        aircraft("hold1", heading: 220, lat: 42.3605, lon: -71.0005)
      ]
    }
    buffer = [
      frame_with("hold1", ts - 100, heading: 300, lat: 42.36, lon: -71.00),
      frame_with("hold1", ts - 75, heading: 359, lat: 42.361, lon: -71.001),
      frame_with("hold1", ts - 50, heading: 60, lat: 42.359, lon: -70.999),
      frame_with("hold1", ts - 25, heading: 140, lat: 42.3602, lon: -71.0002)
    ]

    flags = detect(frame, buffer)

    assert_equal "holding_pattern", flags.first.fetch("rule")
    assert_operator flags.first.fetch("evidence").fetch("cumulative_turn_deg"), :>=, 270
  end

  def test_malformed_aircraft_does_not_crash_scan
    frame = {
      "ts" => 1782145700,
      "aircraft" => [
        { "icao24" => "bad", "on_ground" => false, "lat" => nil, "lon" => -71.0 },
        nil,
        aircraft("ok1", squawk: "7600", lat: 42.37, lon: -71.02)
      ]
    }

    flags = detect(frame, [])

    assert_equal ["ok1"], flags.map { |flag| flag.fetch("icao24") }
  end

  private

  def holding_buffer_for(ts)
    [
      frame_with("a4996b", ts - 105, heading: 92, lat: 42.4510, lon: -70.9520),
      frame_with("a4996b", ts - 80, heading: 175, lat: 42.4520, lon: -70.9510),
      frame_with("a4996b", ts - 55, heading: 255, lat: 42.4500, lon: -70.9530),
      frame_with("a4996b", ts - 30, heading: 335, lat: 42.4515, lon: -70.9525)
    ]
  end

  def frame_with(icao24, ts, heading:, lat:, lon:)
    {
      "ts" => ts,
      "aircraft" => [
        aircraft(icao24, heading: heading, lat: lat, lon: lon)
      ]
    }
  end

  def aircraft(icao24, attrs = {})
    {
      "icao24" => icao24,
      "callsign" => attrs.fetch(:callsign, nil),
      "lat" => attrs.fetch(:lat, 42.36),
      "lon" => attrs.fetch(:lon, -71.0),
      "baro_alt_ft" => attrs.fetch(:baro_alt_ft, 5000),
      "velocity_kt" => attrs.fetch(:velocity_kt, 240),
      "heading" => attrs.fetch(:heading, 90),
      "vert_rate_fpm" => attrs.fetch(:vert_rate_fpm, 0),
      "on_ground" => attrs.fetch(:on_ground, false),
      "squawk" => attrs.fetch(:squawk, "1200"),
      "last_contact" => attrs.fetch(:last_contact, 1782145700)
    }
  end
end
