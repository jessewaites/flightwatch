#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/flightwatch_eval"
require_relative "run_detector_gate"
require_relative "run_investigator_gate"
require "time"

config = FlightWatch::Eval.read_json(File.join(__dir__, "scenario.json"))
plant_result = FlightWatch::Eval::ScenarioPlanter.new(config).plant

detector_mode = ENV.fetch("DETECT_IMPL", "auto")
detector_result = FlightWatch::Eval::DetectorGate.new(detector_mode).run
FlightWatch::Eval.write_json(File.join(__dir__, "detector_results.json"), detector_result)

investigator_result = FlightWatch::Eval::InvestigatorGate
                      .new(File.join(__dir__, "fixtures", "investigator_cases.json"))
                      .run
FlightWatch::Eval.write_json(File.join(__dir__, "evals.json"), investigator_result)

summary = investigator_result.fetch("summary")
benchmark = {
  "generated_at" => Time.now.utc.iso8601,
  "scored_artifact" => "investigator_skill_quality",
  "planted_capture" => plant_result.fetch("output"),
  "detector_gate" => {
    "status" => detector_result.fetch("status"),
    "detector_mode" => detector_result.fetch("detector_mode"),
    "cases_passed" => detector_result.fetch("cases").count { |test_case| test_case.fetch("pass") },
    "cases_total" => detector_result.fetch("cases").length
  },
  "investigator_gate" => {
    "status" => investigator_result.fetch("status"),
    "skill_file_present" => investigator_result.fetch("skill_file_present"),
    "runs_per_without_skill_case" => investigator_result.fetch("runs_per_without_skill_case"),
    "with_skill" => summary.fetch("with_skill"),
    "without_skill" => summary.fetch("without_skill"),
    "delta_accuracy" => summary.fetch("delta_accuracy")
  }
}
FlightWatch::Eval.write_json(File.join(FlightWatch::Eval::ROOT, "benchmark.json"), benchmark)

ok = detector_result.fetch("status") == "PASS" && investigator_result.fetch("status") == "PASS"
puts JSON.pretty_generate(
  "status" => ok ? "PASS" : "FAIL",
  "planted_capture" => plant_result.fetch("output"),
  "evals_json" => "evals/evals.json",
  "benchmark_json" => "benchmark.json",
  "detector_gate" => detector_result.fetch("status"),
  "investigator_gate" => investigator_result.fetch("status"),
  "delta_accuracy" => summary.fetch("delta_accuracy")
)
exit(ok ? 0 : 1)
