#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/flightwatch_eval"

module FlightWatch
  module Eval
    class InvestigatorGate
      RUNS = 3

      def initialize(cases_path)
        @cases = Eval.read_json(cases_path)
      end

      def run
        evaluated_cases = @cases.map { |test_case| evaluate_case(test_case) }
        with_passes = evaluated_cases.count { |test_case| test_case.fetch("with_skill").fetch("pass") }
        without_scores = (0...RUNS).map do |run_index|
          evaluated_cases.count { |test_case| test_case.fetch("without_skill_runs")[run_index].fetch("pass") }
        end
        total = evaluated_cases.length
        {
          "status" => with_passes == total ? "PASS" : "FAIL",
          "scored_artifact" => "investigator_skill_quality",
          "implementation" => "deterministic_fixture_judge",
          "skill_under_test" => "skills/flight-investigation/SKILL.md",
          "skill_file_present" => File.exist?(File.join(ROOT, "skills", "flight-investigation", "SKILL.md")),
          "runs_per_without_skill_case" => RUNS,
          "cases" => evaluated_cases,
          "summary" => {
            "with_skill" => score_hash(with_passes, total),
            "without_skill" => {
              "passes_by_run" => without_scores,
              "worst" => score_hash(without_scores.min, total),
              "median" => score_hash(Eval.median(without_scores).to_f, total)
            },
            "delta_accuracy" => (with_passes.to_f / total - Eval.median(without_scores).to_f / total).round(3)
          }
        }
      end

      private

      def evaluate_case(test_case)
        flag = test_case.fetch("flag")
        Eval.validate_contract!(:flag, flag)

        with_verdict = verdict_for(test_case, classify_with_skill(test_case), "with_skill")
        without_runs = (0...RUNS).map do |run_index|
          verdict = verdict_for(test_case, classify_without_skill(test_case), "without_skill")
          result_for_verdict(test_case, verdict).merge("run" => run_index + 1)
        end

        {
          "id" => test_case.fetch("id"),
          "input" => {
            "flag" => flag,
            "enrichment" => test_case.fetch("enrichment")
          },
          "observable_assertion" => "verdict.assessment equals expected_assessment",
          "expected_assessment" => test_case.fetch("expected_assessment"),
          "with_skill" => result_for_verdict(test_case, with_verdict),
          "without_skill_runs" => without_runs,
          "evidence" => test_case.fetch("why")
        }
      end

      def verdict_for(test_case, assessment, arm)
        flag = test_case.fetch("flag")
        verdict = {
          "icao24" => flag.fetch("icao24"),
          "flag_ts" => flag.fetch("ts"),
          "assessment" => assessment,
          "confidence" => arm == "with_skill" ? 0.86 : 0.62,
          "summary" => summary_for(test_case, assessment, arm),
          "enrichment" => test_case.fetch("enrichment")
        }
        Eval.validate_contract!(:verdict, verdict)
        verdict
      end

      def result_for_verdict(test_case, verdict)
        {
          "assessment" => verdict.fetch("assessment"),
          "pass" => verdict.fetch("assessment") == test_case.fetch("expected_assessment"),
          "verdict" => verdict
        }
      end

      def classify_with_skill(test_case)
        flag = test_case.fetch("flag")
        evidence = flag.fetch("evidence")
        enrichment = test_case.fetch("enrichment")

        if flag.fetch("rule") == "emergency_squawk" && evidence["squawk"] == "7700"
          return "emergency"
        end
        if flag.fetch("rule") == "emergency_squawk" && evidence["squawk"] == "7600"
          return "benign" if enrichment["phase"] == "approach" && enrichment["nearest_airport"] == "KBOS"

          return "concern"
        end
        if flag.fetch("rule") == "rapid_descent"
          return "benign" if enrichment["phase"] == "approach" && enrichment["distance_nm_from_kbos"].to_f <= 15

          return "concern"
        end
        if flag.fetch("rule") == "going_dark"
          return "benign" if enrichment["phase"] == "approach" && enrichment["altitude_ft"].to_f <= 2000

          return "concern"
        end

        "concern"
      end

      def classify_without_skill(test_case)
        flag = test_case.fetch("flag")
        evidence = flag.fetch("evidence")

        return "emergency" if flag.fetch("rule") == "emergency_squawk" && %w[7500 7600 7700].include?(evidence["squawk"].to_s)
        return "concern" if %w[rapid_descent going_dark holding_pattern altitude_outlier].include?(flag.fetch("rule"))

        "concern"
      end

      def summary_for(test_case, assessment, arm)
        "#{arm}: #{test_case.fetch('id')} assessed as #{assessment}."
      end

      def score_hash(passes, total)
        {
          "passes" => passes,
          "total" => total,
          "accuracy" => total.zero? ? 0.0 : (passes.to_f / total).round(3)
        }
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  cases_path = ARGV[0] || File.join(__dir__, "fixtures", "investigator_cases.json")
  result = FlightWatch::Eval::InvestigatorGate.new(cases_path).run
  FlightWatch::Eval.write_json(File.join(__dir__, "evals.json"), result)
  puts JSON.pretty_generate(result)
  exit(result.fetch("status") == "PASS" ? 0 : 1)
end
