#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/flightwatch_eval"

config_path = ARGV[0] || File.join(__dir__, "scenario.json")
config = FlightWatch::Eval.read_json(config_path)
result = FlightWatch::Eval::ScenarioPlanter.new(config).plant

puts JSON.pretty_generate(
  "status" => "ok",
  "planted_output" => result.fetch("output"),
  "applied" => result.fetch("applied")
)
