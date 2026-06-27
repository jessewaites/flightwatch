# frozen_string_literal: true

require "minitest/autorun"

require_relative "../lib/flightwatch/data"

class TestRollingBuffer < Minitest::Test
  RAW_PATH = File.expand_path("../flightwatch-boston-raw-2026-06-22.jsonl", __dir__)

  def test_returns_recent_track_for_queried_icao24
    buffer = FlightWatch::Data::RollingBuffer.new(max_frames: 60)
    replay = FlightWatch::Data::ReplayHarness.new(path: RAW_PATH)

    replay.each_frame { |frame| buffer.ingest(frame) }
    track = buffer.recent_track("a32367")

    assert_operator track.length, :>, 1
    assert_operator track.length, :<=, 60
    assert track.all? { |point| point.fetch("icao24") == "a32367" }
    assert track.all? { |point| point.key?("lat") && point.key?("lon") }
    assert_equal 1_782_146_471, track.last.fetch("ts")
  end

  def test_keeps_only_last_sixty_frames_per_plane
    buffer = FlightWatch::Data::RollingBuffer.new(max_frames: 60)

    70.times do |index|
      buffer.ingest(frame_for("abc123", ts: 1_000 + index, last_contact: 1_000 + index))
    end

    track = buffer.recent_track("abc123")
    assert_equal 60, track.length
    assert_equal 1_010, track.first.fetch("ts")
    assert_equal 1_069, track.last.fetch("ts")
  end

  def test_evicts_plane_after_last_contact_is_stale
    buffer = FlightWatch::Data::RollingBuffer.new(evict_after_seconds: 300)

    buffer.ingest(frame_for("abc123", ts: 1_000, last_contact: 1_000))
    assert buffer.include?("abc123")

    buffer.ingest(frame_for("fresh1", ts: 1_301, last_contact: 1_301))

    refute buffer.include?("abc123")
    assert buffer.include?("fresh1")
  end

  def frame_for(icao24, ts:, last_contact:)
    {
      "ts" => ts,
      "aircraft" => [
        {
          "icao24" => icao24,
          "callsign" => "TEST",
          "lat" => 42.3,
          "lon" => -71.0,
          "baro_alt_ft" => 1_000,
          "velocity_kt" => 100,
          "heading" => 90,
          "vert_rate_fpm" => 0,
          "on_ground" => false,
          "squawk" => "1200",
          "last_contact" => last_contact
        }
      ]
    }
  end
end
