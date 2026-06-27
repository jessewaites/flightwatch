# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../../contracts/validate"

module FlightWatch
  module Eval
    ROOT = File.expand_path("../..", __dir__)
    MPS_TO_KT = 1.9438444924406
    M_TO_FT = 3.2808398950131
    MPS_TO_FPM = 196.85039370079
    FT_TO_M = 0.3048
    FPM_TO_MPS = 0.00508
    EARTH_RADIUS_NM = 3440.065

    module_function

    def read_json(path)
      JSON.parse(File.read(path))
    end

    def write_json(path, obj)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(obj) + "\n")
    end

    def load_raw_frames(path)
      File.readlines(path).map { |line| JSON.parse(line) }
    end

    def write_jsonl(path, rows)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") do |f|
        rows.each { |row| f.puts(JSON.generate(row)) }
      end
    end

    def deep_copy(obj)
      JSON.parse(JSON.generate(obj))
    end

    def normalize_frame(raw)
      {
        "ts" => raw.fetch("time").to_i,
        "aircraft" => raw.fetch("states").map { |state| normalize_state(state) }
      }
    end

    def normalize_state(state)
      {
        "icao24" => state[0].to_s,
        "callsign" => blank_to_nil(state[1].to_s.strip),
        "lat" => state[6],
        "lon" => state[5],
        "baro_alt_ft" => state[7].nil? ? nil : (state[7] * M_TO_FT).round(1),
        "velocity_kt" => state[9].nil? ? nil : (state[9] * MPS_TO_KT).round(1),
        "heading" => state[10],
        "vert_rate_fpm" => state[11].nil? ? nil : (state[11] * MPS_TO_FPM).round(1),
        "on_ground" => state[8] == true,
        "squawk" => state[14].nil? ? nil : state[14].to_s,
        "last_contact" => state[4].to_i
      }
    end

    def blank_to_nil(value)
      value.nil? || value == "" ? nil : value
    end

    def state_for(raw_frame, icao24)
      raw_frame.fetch("states").find { |state| state[0].to_s == icao24.to_s }
    end

    def validate_contract!(kind, obj)
      ok, errors = FlightWatch::Contracts.validate(kind, obj)
      raise "#{kind} contract failed: #{errors.join(', ')}" unless ok

      true
    end

    def flag_for(frame, aircraft, rule, severity, evidence)
      flag = {
        "icao24" => aircraft.fetch("icao24"),
        "ts" => frame.fetch("ts"),
        "rule" => rule,
        "severity" => severity,
        "lat" => aircraft.fetch("lat"),
        "lon" => aircraft.fetch("lon"),
        "evidence" => evidence
      }
      validate_contract!(:flag, flag)
      flag
    end

    def distance_nm(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180.0
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      a = Math.sin(dlat / 2.0)**2 +
          Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2.0)**2
      2.0 * EARTH_RADIUS_NM * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))
    end

    def median(values)
      sorted = values.sort
      return nil if sorted.empty?

      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0)
    end

    module ReferenceDetect
      module_function

      def detect(frame, buffer)
        flags = []
        frame.fetch("aircraft").each do |aircraft|
          next if aircraft["on_ground"]
          next if aircraft["lat"].nil? || aircraft["lon"].nil?

          flags.concat(detect_aircraft(frame, buffer, aircraft))
        end
        flags
      end

      def detect_aircraft(frame, buffer, aircraft)
        flags = []
        squawk = aircraft["squawk"].to_s
        if %w[7500 7600 7700].include?(squawk)
          severity = squawk == "7600" ? "medium" : "high"
          flags << Eval.flag_for(frame, aircraft, "emergency_squawk", severity, { "squawk" => squawk })
        end

        vert_rate = aircraft["vert_rate_fpm"]
        if vert_rate && vert_rate < -2360
          flags << Eval.flag_for(frame, aircraft, "rapid_descent", "medium", { "vert_rate_fpm" => vert_rate })
        end

        gap = frame.fetch("ts") - aircraft.fetch("last_contact")
        prior = previous_aircraft(buffer, aircraft.fetch("icao24"))
        prior_gap = prior ? prior.fetch("frame_ts") - prior.fetch("aircraft").fetch("last_contact") : nil
        if gap >= 240 && prior_gap && prior_gap < 180
          flags << Eval.flag_for(frame, aircraft, "going_dark", "high", { "last_contact_gap_s" => gap })
        end

        if holding_pattern?(frame, buffer, aircraft)
          flags << Eval.flag_for(frame, aircraft, "holding_pattern", "medium", holding_evidence(frame, buffer, aircraft))
        end

        flags
      end

      def previous_aircraft(buffer, icao24)
        buffer.reverse_each do |past_frame|
          ac = past_frame.fetch("aircraft").find { |candidate| candidate["icao24"] == icao24 }
          return { "frame_ts" => past_frame.fetch("ts"), "aircraft" => ac } if ac
        end
        nil
      end

      def track_samples(frame, buffer, aircraft)
        samples = []
        (buffer + [frame]).each do |candidate_frame|
          candidate = candidate_frame.fetch("aircraft").find { |ac| ac["icao24"] == aircraft["icao24"] }
          next unless candidate
          next if candidate["lat"].nil? || candidate["lon"].nil? || candidate["heading"].nil?
          next if candidate["on_ground"]

          samples << candidate.merge("sample_ts" => candidate_frame.fetch("ts"))
        end
        samples.last(10)
      end

      def holding_pattern?(frame, buffer, aircraft)
        samples = track_samples(frame, buffer, aircraft)
        return false if samples.length < 7

        headings = samples.map { |sample| sample.fetch("heading").to_f }
        deltas = []
        headings.each_cons(2) { |from, to| deltas << heading_delta(from, to) }
        nonzero = deltas.reject { |delta| delta.abs < 5.0 }
        return false if nonzero.length < 5

        positive = nonzero.count { |delta| delta > 0 }
        negative = nonzero.count { |delta| delta < 0 }
        consistent_direction = [positive, negative].max.to_f / nonzero.length >= 0.8
        return false unless consistent_direction

        cumulative_turn = nonzero.map(&:abs).inject(0.0, :+)
        return false if cumulative_turn < 270.0

        max_radius_nm(samples) <= 3.0
      end

      def heading_delta(from, to)
        delta = (to - from) % 360.0
        delta > 180.0 ? delta - 360.0 : delta
      end

      def max_radius_nm(samples)
        lat = samples.map { |sample| sample.fetch("lat").to_f }.inject(0.0, :+) / samples.length
        lon = samples.map { |sample| sample.fetch("lon").to_f }.inject(0.0, :+) / samples.length
        samples.map { |sample| Eval.distance_nm(lat, lon, sample.fetch("lat").to_f, sample.fetch("lon").to_f) }.max || 99.0
      end

      def holding_evidence(frame, buffer, aircraft)
        samples = track_samples(frame, buffer, aircraft)
        headings = samples.map { |sample| sample.fetch("heading").to_f }
        cumulative_turn = headings.each_cons(2).map { |from, to| heading_delta(from, to).abs }.inject(0.0, :+)
        {
          "samples" => samples.length,
          "cumulative_turn_deg" => cumulative_turn.round(1),
          "max_radius_nm" => max_radius_nm(samples).round(2)
        }
      end
    end

    module DetectorAdapter
      module_function

      def load(mode)
        case mode
        when "reference"
          new_reference
        when "repo"
          new_repo
        else
          path = File.join(ROOT, "skills", "flight-anomaly-rules", "scripts", "detect.rb")
          File.exist?(path) ? new_repo : new_reference
        end
      end

      def new_reference
        lambda { |frame, buffer| ReferenceDetect.detect(frame, buffer) }
      end

      def new_repo
        path = File.join(ROOT, "skills", "flight-anomaly-rules", "scripts", "detect.rb")
        raise "repo detector not found at #{path}" unless File.exist?(path)

        Kernel.load path
        if defined?(FlightWatch::Detection) && FlightWatch::Detection.respond_to?(:detect)
          return lambda { |frame, buffer| FlightWatch::Detection.detect(frame, buffer) }
        end
        if defined?(FlightWatch::Detect) && FlightWatch::Detect.respond_to?(:detect)
          return lambda { |frame, buffer| FlightWatch::Detect.detect(frame, buffer) }
        end
        if Object.private_method_defined?(:detect)
          return lambda { |frame, buffer| Object.send(:detect, frame, buffer) }
        end

        raise "repo detector loaded but no supported detect(frame, buffer) entrypoint was found"
      end
    end

    class ScenarioPlanter
      def initialize(config)
        @config = config
      end

      def plant
        input_path = File.join(ROOT, @config.fetch("raw_input"))
        output_path = File.join(ROOT, @config.fetch("planted_output"))
        frames = Eval.deep_copy(Eval.load_raw_frames(input_path))
        applied = []
        @config.fetch("plant").each do |entry|
          applied << apply_entry(frames, entry)
        end
        Eval.write_jsonl(output_path, frames)
        { "output" => @config.fetch("planted_output"), "applied" => applied }
      end

      private

      def apply_entry(frames, entry)
        case entry.fetch("rule")
        when "emergency_squawk"
          apply_range(frames, entry) do |frame, state, _idx|
            airborne!(state)
            state[14] = entry.fetch("squawk").to_s
            state[4] = frame.fetch("time")
          end
        when "rapid_descent"
          apply_range(frames, entry) do |frame, state, _idx|
            airborne!(state)
            state[11] = entry.fetch("vert_rate_fpm").to_f * FPM_TO_MPS
            state[4] = frame.fetch("time")
          end
        when "going_dark"
          apply_range(frames, entry) do |frame, state, _idx|
            airborne!(state)
            stale = entry.fetch("stale_seconds", 360).to_i
            state[3] = frame.fetch("time") - stale
            state[4] = frame.fetch("time") - stale
          end
        when "holding_pattern"
          headings = [350, 20, 60, 100, 140, 180, 220, 260, 300, 340, 20, 60]
          apply_range(frames, entry) do |frame, state, offset|
            airborne!(state)
            angle = offset * 40.0 * Math::PI / 180.0
            radius = entry.fetch("radius_deg", 0.01).to_f
            state[6] = entry.fetch("center_lat").to_f + Math.sin(angle) * radius
            state[5] = entry.fetch("center_lon").to_f + Math.cos(angle) * radius
            state[7] = 3000 * FT_TO_M
            state[9] = 145 / MPS_TO_KT
            state[10] = headings[offset % headings.length]
            state[11] = 0.0
            state[14] ||= "1200"
            state[3] = frame.fetch("time")
            state[4] = frame.fetch("time")
          end
        else
          raise "unknown plant rule: #{entry.fetch('rule')}"
        end
      end

      def apply_range(frames, entry)
        from = (entry["from_frame"] || entry["at_frame"]).to_i
        to = (entry["to_frame"] || entry["at_frame"] || from).to_i
        touched = []
        (from..to).each_with_index do |frame_index, offset|
          frame = frames.fetch(frame_index)
          state = Eval.state_for(frame, entry.fetch("icao24"))
          next unless state

          yield(frame, state, offset)
          touched << frame_index
        end
        {
          "id" => entry.fetch("id"),
          "icao24" => entry.fetch("icao24"),
          "rule" => entry.fetch("rule"),
          "expected_frame_count" => to - from + 1,
          "frames_touched" => touched,
          "status" => range_status(touched.length, to - from + 1)
        }
      end

      def range_status(touched_count, expected_count)
        return "missing_aircraft" if touched_count.zero?
        return "partial" if touched_count < expected_count

        "applied"
      end

      def airborne!(state)
        state[8] = false
        state[7] ||= 2000 * FT_TO_M
        state[9] ||= 120 / MPS_TO_KT
        state[10] ||= 90.0
      end
    end
  end
end
