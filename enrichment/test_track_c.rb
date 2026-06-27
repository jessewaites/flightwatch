# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../agents/investigator"

class TrackCInvestigatorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_offline_investigator_writes_contract_valid_verdict
    Dir.mktmpdir("flightwatch-track-c") do |dir|
      workspace = File.join(dir, "workspace")
      FileUtils.mkdir_p(File.join(workspace, "flags"))
      FileUtils.mkdir_p(File.join(workspace, "verdicts"))
      FileUtils.mkdir_p(File.join(workspace, "observe"))
      FileUtils.cp(
        File.join(ROOT, "contracts", "fixtures", "workspace", "flags", "a35e3d-1782145700.json"),
        File.join(workspace, "flags", "a35e3d-1782145700.json")
      )

      FlightWatch::Investigator::Runner.new(
        workspace: workspace,
        offline: true,
        once: true,
        use_skill: true
      ).run

      verdict_path = File.join(workspace, "verdicts", "a35e3d-1782145700.json")
      assert File.exist?(verdict_path), "verdict was not written"

      verdict = JSON.parse(File.read(verdict_path))
      ok, errors = FlightWatch::Contracts.validate(:verdict, verdict)
      assert ok, errors.join(", ")
      assert_equal "KBOS", verdict.dig("enrichment", "nearest_airport")
      refute_empty verdict.dig("enrichment", "metar").to_s
      refute_empty verdict.dig("enrichment", "aircraft_type").to_s
    end
  end

  def test_skill_changes_lost_comms_fog_approach_assessment
    Dir.mktmpdir("flightwatch-track-c") do |dir|
      workspace = File.join(dir, "workspace")
      %w[flags verdicts observe].each { |subdir| FileUtils.mkdir_p(File.join(workspace, subdir)) }
      flag = {
        "icao24" => "a47597",
        "ts" => 1782141713,
        "rule" => "emergency_squawk",
        "severity" => "high",
        "lat" => 42.36,
        "lon" => -71.02,
        "evidence" => { "squawk" => "7600", "baro_alt_ft" => 2400 }
      }
      File.write(File.join(workspace, "flags", "a47597-1782141713.json"), JSON.generate(flag))

      runner = FlightWatch::Investigator::Runner.new(
        workspace: workspace,
        offline: true,
        once: true,
        use_skill: true
      )
      enrichment = {
        "metar" => File.read(File.join(ROOT, "enrichment", "fixtures", "metar", "KBOS_fog.txt")),
        "nearest_airport" => "KBOS",
        "aircraft_type" => "unknown",
        "surface_context" => "KBOS terminal approach area",
        "nearest_airport_nm" => 2.0
      }
      skilled = runner.send(:skilled_local_judge, flag, enrichment)
      baseline = runner.send(:baseline_local_judge, flag, enrichment)

      assert_equal "benign", skilled["assessment"]
      assert_equal "concern", baseline["assessment"]
    end
  end
end
