# frozen_string_literal: true

require "json"
require "minitest/autorun"

require_relative "../lib/flightwatch/data"
require_relative "../../contracts/validate"

class TestNormalizer < Minitest::Test
  RAW_PATH = File.expand_path("../flightwatch-boston-raw-2026-06-22.jsonl", __dir__)

  def first_raw
    JSON.parse(File.readlines(RAW_PATH, chomp: true).first)
  end

  def test_all_replay_frames_validate_against_frozen_frame_contract
    replay = FlightWatch::Data::ReplayHarness.new(path: RAW_PATH)

    replay.each_frame.with_index do |frame, index|
      ok, errors = FlightWatch::Contracts.validate(:frame, frame)
      assert ok, "frame #{index} failed contract validation: #{errors.join(", ")}"
    end
  end

  def test_normalizes_authoritative_indices_and_units
    frame = FlightWatch::Data::Normalizer.normalize(first_raw)
    aircraft = frame.fetch("aircraft")

    bcp001 = aircraft.find { |item| item.fetch("icao24") == "5003bc" }
    assert_equal "BCP001", bcp001.fetch("callsign")
    assert_equal "2511", bcp001.fetch("squawk"), "squawk must come from index 14, not spi index 15"
    assert_equal true, bcp001.fetch("on_ground")

    rpa4666 = aircraft.find { |item| item.fetch("icao24") == "a0835d" }
    assert_equal 2_100, rpa4666.fetch("baro_alt_ft")
    assert_in_delta 192.65, rpa4666.fetch("velocity_kt"), 0.01
    assert_in_delta(-1_151.57, rpa4666.fetch("vert_rate_fpm"), 0.01)
    assert_equal 1_782_145_125, rpa4666.fetch("last_contact")
    assert_equal false, rpa4666.fetch("on_ground")
  end

  def test_preserves_epoch_seconds
    frame = FlightWatch::Data::Normalizer.normalize(first_raw)

    assert_equal 1_782_145_125, frame.fetch("ts")
    assert frame.fetch("ts") < 10_000_000_000
    assert frame.fetch("aircraft").all? { |aircraft| aircraft.fetch("last_contact") < 10_000_000_000 }
  end
end
