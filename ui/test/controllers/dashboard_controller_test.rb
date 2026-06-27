require "test_helper"
require "fileutils"
require "tmpdir"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders the fixture-backed dashboard" do
    previous = ENV["FLIGHTWATCH_FIXTURES"]
    ENV["FLIGHTWATCH_FIXTURES"] = "1"

    get root_path

    assert_response :success
    assert_select "h1", "FlightWatch"
    assert_select "#anomaly-feed article", minimum: 3
    assert_select "#synthesis-feed article", minimum: 1
    assert_includes response.body, "KBOS"
  ensure
    ENV["FLIGHTWATCH_FIXTURES"] = previous
  end

  test "writes mode changes to the workspace file bus" do
    Dir.mktmpdir do |dir|
      previous = ENV["FLIGHTWATCH_WORKSPACE"]
      ENV["FLIGHTWATCH_WORKSPACE"] = dir

      post mode_path, params: { source: "realtime" }, as: :json

      assert_response :success
      mode_file = Pathname.new(dir).join("control", "mode.json")
      assert mode_file.exist?
      assert_equal "realtime", JSON.parse(File.read(mode_file))["source"]
    ensure
      ENV["FLIGHTWATCH_WORKSPACE"] = previous
    end
  end

  test "generates a current synthesis on demand" do
    Dir.mktmpdir do |dir|
      previous = ENV["FLIGHTWATCH_WORKSPACE"]
      ENV["FLIGHTWATCH_WORKSPACE"] = dir
      ts = Time.now.to_i

      %w[flags verdicts weather situations].each { |kind| FileUtils.mkdir_p(Pathname.new(dir).join(kind)) }
      File.write(Pathname.new(dir).join("flags", "a35e3d-#{ts}.json"), JSON.generate({
        "icao24" => "a35e3d",
        "ts" => ts,
        "rule" => "emergency_squawk",
        "severity" => "high",
        "lat" => 42.4012,
        "lon" => -71.0488,
        "evidence" => { "squawk" => "7700" }
      }))
      File.write(Pathname.new(dir).join("verdicts", "a35e3d-#{ts}.json"), JSON.generate({
        "icao24" => "a35e3d",
        "flag_ts" => ts,
        "assessment" => "emergency",
        "confidence" => 0.95,
        "summary" => "Squawking 7700 toward KBOS with no benign explanation.",
        "enrichment" => {}
      }))
      File.write(Pathname.new(dir).join("weather", "kbos.json"), JSON.generate({
        "summary" => "KBOS winds 210 at 12 kt with 10 statute miles visibility."
      }))

      post synthesis_path, as: :json

      assert_response :success
      situation = JSON.parse(response.body).fetch("situation")
      assert_equal "KBOS", situation["airport"]
      assert_equal [ "a35e3d" ], situation["icao24s"]
      assert_includes situation["summary"], "The most recent investigations say"
      assert_includes situation["summary"], "\n\n"
      assert Pathname.new(dir).join("situations", "#{situation["id"]}.json").exist?
    ensure
      ENV["FLIGHTWATCH_WORKSPACE"] = previous
    end
  end
end
