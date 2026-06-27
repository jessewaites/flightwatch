# frozen_string_literal: true
#
# FlightWatch — Phase 0 frozen contract validator.
# Pure Ruby, ZERO gems (build-day reliability). This file is the EXECUTABLE source of
# truth for the seams every track shares. contracts/README.md documents the same shapes.
#
# Usage from any agent, BEFORE writing to workspace/:
#   require_relative "../contracts/validate"            # adjust path
#   ok, errors = FlightWatch::Contracts.validate(:flag, hash)
#   raise "contract: #{errors.join(', ')}" unless ok
#
# Run directly to validate every fixture against these schemas:
#   ruby contracts/validate.rb
#
# FROZEN after Phase 0. A schema change is a STOP-and-renegotiate event, never a silent edit.
module FlightWatch
  module Contracts
    RULES           = %w[emergency_squawk rapid_descent going_dark holding_pattern altitude_outlier].freeze
    SEVERITIES      = %w[low medium high].freeze
    ASSESSMENTS     = %w[benign concern emergency].freeze
    SITUATION_KINDS = %w[ground_stop weather_diversion runway_closure].freeze

    # ALL timestamps are epoch SECONDS (integer), never milliseconds.
    BBOX = { lamin: 42.2, lomin: -71.2, lamax: 42.5, lomax: -70.9 }.freeze

    # field => [type, required?, nullable?, enum_or_nil]
    # types: :string :integer :number :boolean :array :hash
    AIRCRAFT_SCHEMA = {
      "icao24"       => [:string,  true,  false, nil],
      "callsign"     => [:string,  false, true,  nil],
      "lat"          => [:number,  true,  true,  nil],
      "lon"          => [:number,  true,  true,  nil],
      "baro_alt_ft"  => [:number,  true,  true,  nil],
      "velocity_kt"  => [:number,  true,  true,  nil],
      "heading"      => [:number,  true,  true,  nil],
      "vert_rate_fpm"=> [:number,  true,  true,  nil],
      "on_ground"    => [:boolean, true,  false, nil],
      "squawk"       => [:string,  true,  true,  nil],
      "last_contact" => [:integer, true,  false, nil]
    }.freeze

    FRAME_SCHEMA = {
      "ts"       => [:integer, true, false, nil],
      "aircraft" => [:array,   true, false, nil] # each element validated against AIRCRAFT_SCHEMA
    }.freeze

    FLAG_SCHEMA = {
      "icao24"   => [:string,  true, false, nil],
      "ts"       => [:integer, true, false, nil],
      "rule"     => [:string,  true, false, RULES],
      "severity" => [:string,  true, false, SEVERITIES],
      "lat"      => [:number,  true, false, nil],
      "lon"      => [:number,  true, false, nil],
      "evidence" => [:hash,    true, false, nil]
    }.freeze

    VERDICT_SCHEMA = {
      "icao24"     => [:string, true, false, nil],
      "flag_ts"    => [:integer,true, false, nil],
      "assessment" => [:string, true, false, ASSESSMENTS],
      "confidence" => [:number, true, false, nil], # 0.0..1.0, range-checked below
      "summary"    => [:string, true, false, nil],
      "enrichment" => [:hash,   true, false, nil]
    }.freeze

    SITUATION_SCHEMA = {
      "id"      => [:string,  true, false, nil],
      "ts"      => [:integer, true, false, nil],
      "kind"    => [:string,  true, false, SITUATION_KINDS],
      "airport" => [:string,  true, false, nil],
      "icao24s" => [:array,   true, false, nil], # array of strings
      "summary" => [:string,  true, false, nil]
    }.freeze

    SCHEMAS = {
      frame:     FRAME_SCHEMA,
      flag:      FLAG_SCHEMA,
      verdict:   VERDICT_SCHEMA,
      situation: SITUATION_SCHEMA
    }.freeze

    module_function

    # Returns [true, []] on success, [false, ["msg", ...]] on failure.
    def validate(kind, obj, prefix = nil)
      schema = SCHEMAS[kind] or return [false, ["unknown contract kind: #{kind.inspect}"]]
      return [false, ["#{label(prefix)}expected a Hash, got #{obj.class}"]] unless obj.is_a?(Hash)

      errors = []
      schema.each do |field, (type, required, nullable, enum)|
        present = obj.key?(field)
        value   = obj[field]

        if !present
          errors << "#{label(prefix)}missing required field '#{field}'" if required
          next
        end
        if value.nil?
          errors << "#{label(prefix)}'#{field}' must not be null" unless nullable
          next
        end
        unless type_ok?(value, type)
          errors << "#{label(prefix)}'#{field}' must be #{type}, got #{value.class}"
          next
        end
        if enum && !enum.include?(value)
          errors << "#{label(prefix)}'#{field}' must be one of #{enum.join('|')}, got #{value.inspect}"
        end
      end

      # nested + range checks
      case kind
      when :frame
        Array(obj["aircraft"]).each_with_index do |ac, i|
          ok, errs = validate_aircraft(ac, "aircraft[#{i}].")
          errors.concat(errs) unless ok
        end
      when :verdict
        c = obj["confidence"]
        errors << "#{label(prefix)}'confidence' must be within 0.0..1.0" if c.is_a?(Numeric) && (c < 0 || c > 1)
      when :situation
        Array(obj["icao24s"]).each_with_index do |id, i|
          errors << "#{label(prefix)}icao24s[#{i}] must be a String" unless id.is_a?(String)
        end
      end

      [errors.empty?, errors]
    end

    def validate_aircraft(obj, prefix)
      return [false, ["#{prefix}expected a Hash, got #{obj.class}"]] unless obj.is_a?(Hash)
      errors = []
      AIRCRAFT_SCHEMA.each do |field, (type, required, nullable, _enum)|
        unless obj.key?(field)
          errors << "#{prefix}missing required field '#{field}'" if required
          next
        end
        value = obj[field]
        if value.nil?
          errors << "#{prefix}'#{field}' must not be null" unless nullable
          next
        end
        errors << "#{prefix}'#{field}' must be #{type}, got #{value.class}" unless type_ok?(value, type)
      end
      [errors.empty?, errors]
    end

    def type_ok?(value, type)
      case type
      when :string  then value.is_a?(String)
      when :integer then value.is_a?(Integer)
      when :number  then value.is_a?(Numeric) && !value.is_a?(Complex)
      when :boolean then value == true || value == false
      when :array   then value.is_a?(Array)
      when :hash    then value.is_a?(Hash)
      else false
      end
    end

    def label(prefix)
      prefix ? prefix : ""
    end
  end
end

# --- self-test: validate every fixture when run directly ---
if __FILE__ == $PROGRAM_NAME
  require "json"
  dir = File.join(__dir__, "fixtures")
  checks = {
    frame:     "frame.sample.json",
    flag:      "flag.sample.json",
    verdict:   "verdict.sample.json",
    situation: "situation.sample.json"
  }
  failures = 0
  checks.each do |kind, file|
    path = File.join(dir, file)
    unless File.exist?(path)
      puts "  MISSING  #{file}"; failures += 1; next
    end
    obj = JSON.parse(File.read(path))
    ok, errs = FlightWatch::Contracts.validate(kind, obj)
    if ok
      puts "  OK       #{file} (#{kind})"
    else
      puts "  FAIL     #{file} (#{kind})"
      errs.each { |e| puts "             - #{e}" }
      failures += 1
    end
  end
  # validate the sample workspace files too
  Dir[File.join(dir, "workspace", "flags", "*.json")].sort.each do |p|
    ok, errs = FlightWatch::Contracts.validate(:flag, JSON.parse(File.read(p)))
    puts(ok ? "  OK       workspace/flags/#{File.basename(p)}" : "  FAIL     workspace/flags/#{File.basename(p)}: #{errs.join(', ')}")
    failures += 1 unless ok
  end
  Dir[File.join(dir, "workspace", "verdicts", "*.json")].sort.each do |p|
    ok, errs = FlightWatch::Contracts.validate(:verdict, JSON.parse(File.read(p)))
    puts(ok ? "  OK       workspace/verdicts/#{File.basename(p)}" : "  FAIL     workspace/verdicts/#{File.basename(p)}: #{errs.join(', ')}")
    failures += 1 unless ok
  end
  Dir[File.join(dir, "workspace", "situations", "*.json")].sort.each do |p|
    ok, errs = FlightWatch::Contracts.validate(:situation, JSON.parse(File.read(p)))
    puts(ok ? "  OK       workspace/situations/#{File.basename(p)}" : "  FAIL     workspace/situations/#{File.basename(p)}: #{errs.join(', ')}")
    failures += 1 unless ok
  end
  puts(failures.zero? ? "\nAll contracts + fixtures valid." : "\n#{failures} failure(s).")
  exit(failures.zero? ? 0 : 1)
end
