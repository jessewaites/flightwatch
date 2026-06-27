# frozen_string_literal: true

require "minitest/autorun"

require_relative "../lib/flightwatch/data"

class TestReplayHarness < Minitest::Test
  RAW_PATH = File.expand_path("../flightwatch-boston-raw-2026-06-22.jsonl", __dir__)

  def test_plays_raw_file_frame_by_frame
    replay = FlightWatch::Data::ReplayHarness.new(path: RAW_PATH)
    expected_count = File.readlines(RAW_PATH, chomp: true).reject(&:empty?).length

    frames = replay.each_frame.to_a

    assert_equal expected_count, frames.length
    assert_equal 1_782_145_125, frames.first.fetch("ts")
    assert_equal JSON.parse(File.readlines(RAW_PATH, chomp: true).last).fetch("time"), frames.last.fetch("ts")
    assert_nil replay.next_frame
  end

  def test_default_capture_path_points_at_data_file
    replay = FlightWatch::Data::ReplayHarness.new

    assert_equal RAW_PATH, replay.path
    assert_operator replay.count, :>, 0
  end
end
