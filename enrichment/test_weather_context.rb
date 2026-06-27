# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "weather_context"

class WeatherContextTest < Minitest::Test
  def test_snapshot_from_open_meteo_forecast
    forecast = {
      "latitude" => 42.35753,
      "longitude" => -71.02687,
      "current_units" => {
        "temperature_2m" => "F",
        "visibility" => "ft",
        "wind_speed_10m" => "kn",
        "precipitation" => "inch"
      },
      "current" => {
        "temperature_2m" => 69.2,
        "weather_code" => 1,
        "visibility" => 43_963.252,
        "wind_speed_10m" => 9.0,
        "wind_direction_10m" => 84,
        "wind_gusts_10m" => 11.1,
        "cloud_cover" => 24,
        "precipitation" => 0
      }
    }

    snapshot = FlightWatch::WeatherContext.snapshot_from_forecast(forecast, fetched_at: 1_782_145_820)

    assert_equal "KBOS", snapshot["airport"]
    assert_equal "open-meteo-mcp", snapshot["source"]
    assert_equal 1_782_145_820, snapshot["fetched_at"]
    assert_equal 42.35753, snapshot.dig("location", "lat")
    assert_includes snapshot["summary"], "Open-Meteo KBOS: mainly clear"
    assert_includes snapshot["summary"], "E wind 9 kt gust 11 kt"
    assert_includes snapshot["summary"], "visibility 8.3 sm"
    assert_includes snapshot["summary"], "no precipitation"
  end

  def test_offline_refresh_writes_weather_file
    Dir.mktmpdir("flightwatch-weather") do |workspace|
      snapshot = FlightWatch::WeatherContext.new(workspace_dir: workspace, offline: true).refresh
      path = File.join(workspace, "weather", "kbos.json")

      assert File.exist?(path), "expected weather snapshot to be written"
      persisted = JSON.parse(File.read(path))
      assert_equal snapshot["summary"], persisted["summary"]
      assert_equal "offline-fixture", persisted["source"]
      assert_includes persisted["summary"], "Open-Meteo KBOS"
    end
  end
end
