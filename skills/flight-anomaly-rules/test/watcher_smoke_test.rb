# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "rbconfig"
require "shellwords"
require "tmpdir"

ROOT = File.expand_path("../../..", __dir__)
require File.join(ROOT, "contracts/validate")
load File.join(ROOT, "agents/watcher.rb")

class WatcherSmokeTest < Minitest::Test
  def test_watcher_writes_contract_valid_flags
    Dir.mktmpdir("flightwatch-watcher") do |dir|
      workspace = File.join(dir, "workspace")
      FileUtils.mkdir_p(File.join(workspace, "flags"))
      FileUtils.mkdir_p(File.join(workspace, "observe"))

      command = [
        RbConfig.ruby,
        File.join(ROOT, "agents/watcher.rb"),
        "--offline",
        "--once",
        "--no-skill",
        "--workspace", workspace
      ]
      output = `#{command.map { |part| Shellwords.escape(part) }.join(" ")} 2>&1`
      assert $?.success?, output

      paths = Dir[File.join(workspace, "flags", "*.json")].sort
      assert_equal 2, paths.length

      flags = paths.map { |path| JSON.parse(File.read(path)) }
      assert_equal %w[a35e3d a37c1c], flags.map { |flag| flag.fetch("icao24") }.sort
      flags.each do |flag|
        ok, errors = FlightWatch::Contracts.validate(:flag, flag)
        assert ok, errors.join(", ")
      end
    end
  end

  def test_prioritization_keeps_emergency_squawks_in_fixed_order
    watcher = build_watcher
    flags = [
      flag("tier2", "rapid_descent", "high"),
      flag("radio", "emergency_squawk", "high", "squawk" => "7600"),
      flag("general", "emergency_squawk", "high", "squawk" => "7700"),
      flag("hijack", "emergency_squawk", "high", "squawk" => "7500")
    ]

    ranked = watcher.send(:prioritize, flags)

    assert_equal %w[general hijack radio tier2], ranked.map { |candidate| candidate.fetch("icao24") }
  end

  def test_model_order_parser_accepts_wrappers_arrays_objects_and_fences
    watcher = build_watcher

    assert_equal %w[a b], watcher.send(:parse_model_order, '{"order":["a","b"]}')
    assert_equal %w[a b], watcher.send(:parse_model_order, '["a",{"icao24":"b"}]')
    assert_equal %w[a], watcher.send(:parse_model_order, "```json\n{\"order\":[{\"icao24\":\"a\"}]}\n```")
  end

  private

  def build_watcher
    FlightWatch::Watcher.new(
      workspace: Dir.mktmpdir("flightwatch-watcher"),
      tracks_dir: File.join(ROOT, "workspace/tracks"),
      frame_path: nil,
      frames_path: nil,
      offline: false,
      once: true,
      no_skill: true,
      poll_interval: 1.0,
      max_buffer: 12,
      model: "granite4:micro",
      ollama_base: "http://localhost:11434/v1"
    )
  end

  def flag(icao24, rule, severity, evidence = {})
    {
      "icao24" => icao24,
      "ts" => 1782145700,
      "rule" => rule,
      "severity" => severity,
      "lat" => 42.36,
      "lon" => -71.01,
      "evidence" => evidence
    }
  end
end
