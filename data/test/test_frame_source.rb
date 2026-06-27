# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../lib/flightwatch/data"

class TestFrameSource < Minitest::Test
  FakeSource = Struct.new(:name) do
    def next_frame
      { "ts" => 1, "aircraft" => [{ "icao24" => name }] }
    end
  end

  def test_reads_mode_each_tick_and_switches_without_restart
    Dir.mktmpdir do |dir|
      mode_path = File.join(dir, "mode.json")
      realtime = FakeSource.new("realtime")
      demo = FakeSource.new("demo")
      source = FlightWatch::Data::FrameSource.new(
        realtime_source: realtime,
        demo_source: demo,
        mode_path: mode_path
      )

      File.write(mode_path, JSON.generate("source" => "demo"))
      assert_equal "demo", source.next_frame.fetch("aircraft").first.fetch("icao24")

      File.write(mode_path, JSON.generate("source" => "realtime"))
      assert_equal "realtime", source.next_frame.fetch("aircraft").first.fetch("icao24")
    end
  end

  def test_each_frame_can_drive_bounded_tick_loop
    source = FlightWatch::Data::FrameSource.new(
      realtime_source: FakeSource.new("realtime"),
      demo_source: FakeSource.new("demo"),
      mode_path: "/path/that/does/not/exist"
    )

    frames = []
    source.each_frame(interval_seconds: 0, limit: 3) { |frame| frames << frame }

    assert_equal 3, frames.length
    assert frames.all? { |frame| frame.fetch("aircraft").first.fetch("icao24") == "demo" }
  end
end
