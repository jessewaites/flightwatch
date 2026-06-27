# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

repo_root = File.expand_path("../../..", __dir__)
require File.join(repo_root, "agents", "synthesizer")

def write_json(path, obj)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(obj) + "\n")
end

Dir.mktmpdir("flightwatch-synthesizer-") do |workspace|
  flags_dir = File.join(workspace, "flags")
  verdicts_dir = File.join(workspace, "verdicts")
  situations_dir = File.join(workspace, "situations")
  FileUtils.mkdir_p([flags_dir, verdicts_dir, situations_dir])

  ts = 1_782_145_820
  aircraft = [
    ["a4996b", 42.4510, -70.9520],
    ["a37c1c", 42.4320, -70.9800],
    ["a3a0e1", 42.4060, -71.0300],
    ["a5b2c4", 42.3900, -71.0600],
    ["a1d9f7", 42.3600, -70.9600]
  ]

  aircraft.each_with_index do |(icao24, lat, lon), i|
    flag_ts = ts + i
    write_json(
      File.join(flags_dir, "#{icao24}-#{flag_ts}.json"),
      {
        "icao24" => icao24,
        "ts" => flag_ts,
        "rule" => "holding_pattern",
        "severity" => "medium",
        "lat" => lat,
        "lon" => lon,
        "evidence" => { "cumulative_turn_deg" => 320 + i, "window_s" => 105, "radius_nm" => 2.5 }
      }
    )
    write_json(
      File.join(verdicts_dir, "#{icao24}-#{flag_ts}.json"),
      {
        "icao24" => icao24,
        "flag_ts" => flag_ts,
        "assessment" => "concern",
        "confidence" => 0.74,
        "summary" => "Holding near KBOS with no aircraft-specific emergency.",
        "enrichment" => { "nearest_airport" => "KBOS" }
      }
    )
  end

  written = FlightWatch::Synthesizer.new(workspace_dir: workspace, use_model: false, once: true).run_once
  raise "expected one situation, wrote #{written.length}" unless written.length == 1

  situation = written.first
  ok, errors = FlightWatch::Contracts.validate(:situation, situation)
  raise "invalid situation: #{errors.join(', ')}" unless ok
  raise "expected ground_stop, got #{situation["kind"].inspect}" unless situation["kind"] == "ground_stop"
  raise "expected KBOS, got #{situation["airport"].inspect}" unless situation["airport"] == "KBOS"
  raise "expected five aircraft, got #{situation["icao24s"].length}" unless situation["icao24s"].length == 5
  raise "summary should name a ground stop: #{situation["summary"].inspect}" unless situation["summary"].downcase.include?("ground stop")

  output_path = File.join(situations_dir, "#{situation["id"]}.json")
  raise "expected #{output_path} to be written" unless File.exist?(output_path)

  persisted = JSON.parse(File.read(output_path))
  ok, errors = FlightWatch::Contracts.validate(:situation, persisted)
  raise "persisted situation invalid: #{errors.join(', ')}" unless ok

  puts "OK synthesizer self-test wrote #{output_path}"
end
