# frozen_string_literal: true

# Deterministic FlightWatch anomaly detection.
# Frozen callable signature: detect(frame, buffer) -> [flag]

module FlightWatch
  module AnomalyRules
    EMERGENCY_SQUAWKS = {
      "7700" => "general_emergency",
      "7500" => "hijack",
      "7600" => "radio_failure"
    }.freeze

    RAPID_DESCENT_FPM = -2360
    GOING_DARK_GAP_S = 180
    GOING_DARK_NO_HISTORY_GAP_S = 300
    GOING_DARK_MIN_INCREASE_S = 30
    HOLD_WINDOW_S = 120
    HOLD_MIN_WINDOW_S = 80
    HOLD_MIN_TURN_DEG = 270
    HOLD_MAX_RADIUS_NM = 3.0
    HOLD_MAX_OPPOSITE_TURN_DEG = 60
    ALTITUDE_OUTLIER_MIN_PEERS = 4
    ALTITUDE_OUTLIER_DELTA_FT = 6000

    module_function

    def detect(frame, buffer)
      return [] unless frame.is_a?(Hash)

      ts = integer(frame["ts"])
      aircraft = frame["aircraft"]
      return [] unless ts && aircraft.is_a?(Array)

      aircraft.each_with_object([]) do |state, flags|
        next unless usable_aircraft?(state)

        flag = emergency_squawk_flag(state, ts) ||
               rapid_descent_flag(state, ts) ||
               going_dark_flag(state, ts, buffer) ||
               holding_pattern_flag(state, ts, buffer) ||
               altitude_outlier_flag(state, ts, aircraft)

        flags << flag if flag
      rescue StandardError
        next
      end
    end

    def usable_aircraft?(state)
      state.is_a?(Hash) &&
        !state["on_ground"] &&
        present_string?(state["icao24"]) &&
        number?(state["lat"]) &&
        number?(state["lon"])
    end

    def emergency_squawk_flag(state, ts)
      squawk = state["squawk"].to_s
      return nil unless EMERGENCY_SQUAWKS.key?(squawk)

      build_flag(state, ts, "emergency_squawk", "high", {
        "squawk" => squawk,
        "meaning" => EMERGENCY_SQUAWKS.fetch(squawk)
      })
    end

    def rapid_descent_flag(state, ts)
      rate = number_value(state["vert_rate_fpm"])
      return nil unless rate && rate < RAPID_DESCENT_FPM

      build_flag(state, ts, "rapid_descent", "high", {
        "vert_rate_fpm" => rounded(rate),
        "threshold_fpm" => RAPID_DESCENT_FPM
      })
    end

    def going_dark_flag(state, ts, buffer)
      last_contact = integer(state["last_contact"])
      return nil unless last_contact

      gap = ts - last_contact
      return nil if gap < GOING_DARK_GAP_S

      previous_gaps = history_for(state["icao24"], buffer).map do |sample|
        sample_ts = integer(sample["ts"])
        sample_contact = integer(sample["last_contact"])
        sample_ts && sample_contact ? sample_ts - sample_contact : nil
      end.compact

      growing = if previous_gaps.empty?
                  gap >= GOING_DARK_NO_HISTORY_GAP_S
                else
                  gap >= previous_gaps.max + GOING_DARK_MIN_INCREASE_S
                end
      return nil unless growing

      build_flag(state, ts, "going_dark", gap >= 300 ? "high" : "medium", {
        "gap_s" => gap,
        "last_contact" => last_contact
      })
    end

    def holding_pattern_flag(state, ts, buffer)
      samples = history_for(state["icao24"], buffer)
                .select { |sample| integer(sample["ts"]) && integer(sample["ts"]) >= ts - HOLD_WINDOW_S }
                .push(state.merge("ts" => ts))
                .select { |sample| number?(sample["lat"]) && number?(sample["lon"]) && number?(sample["heading"]) }
                .sort_by { |sample| integer(sample["ts"]) }

      return nil if samples.length < 4

      window_s = integer(samples.last["ts"]) - integer(samples.first["ts"])
      return nil if window_s < HOLD_MIN_WINDOW_S || window_s > HOLD_WINDOW_S

      turns = signed_turns(samples.map { |sample| number_value(sample["heading"]) })
      positive_turn = turns.select(&:positive?).sum
      negative_turn = turns.select(&:negative?).sum.abs
      dominant_turn = [positive_turn, negative_turn].max
      opposite_turn = [positive_turn, negative_turn].min
      return nil if dominant_turn < HOLD_MIN_TURN_DEG
      return nil if opposite_turn > HOLD_MAX_OPPOSITE_TURN_DEG

      radius_nm = radius_nm(samples)
      return nil if radius_nm > HOLD_MAX_RADIUS_NM

      build_flag(state, ts, "holding_pattern", "medium", {
        "cumulative_turn_deg" => rounded(dominant_turn),
        "window_s" => window_s,
        "radius_nm" => rounded(radius_nm),
        "direction" => positive_turn >= negative_turn ? "right" : "left"
      })
    end

    def altitude_outlier_flag(state, ts, aircraft)
      altitude = number_value(state["baro_alt_ft"])
      return nil unless altitude

      peer_altitudes = aircraft.select { |peer| peer.is_a?(Hash) && !peer["on_ground"] }
                               .map { |peer| number_value(peer["baro_alt_ft"]) }
                               .compact
      return nil if peer_altitudes.length < ALTITUDE_OUTLIER_MIN_PEERS

      med = median(peer_altitudes)
      delta = (altitude - med).abs
      return nil if delta < ALTITUDE_OUTLIER_DELTA_FT

      build_flag(state, ts, "altitude_outlier", delta >= 10_000 ? "medium" : "low", {
        "baro_alt_ft" => rounded(altitude),
        "peer_median_ft" => rounded(med),
        "delta_ft" => rounded(delta)
      })
    end

    def build_flag(state, ts, rule, severity, evidence)
      {
        "icao24" => state["icao24"],
        "ts" => ts,
        "rule" => rule,
        "severity" => severity,
        "lat" => number_value(state["lat"]),
        "lon" => number_value(state["lon"]),
        "evidence" => evidence
      }
    end

    def history_for(icao24, buffer)
      frames = normalize_buffer(buffer)
      frames.each_with_object([]) do |frame, samples|
        frame_ts = integer(frame["ts"])
        Array(frame["aircraft"]).each do |state|
          next unless state.is_a?(Hash) && state["icao24"] == icao24

          samples << state.merge("ts" => frame_ts)
        end
      end
    end

    def normalize_buffer(buffer)
      case buffer
      when Array
        buffer.select { |entry| entry.is_a?(Hash) && entry["aircraft"].is_a?(Array) }
      when Hash
        buffer.values.flatten.select { |entry| entry.is_a?(Hash) && entry["aircraft"].is_a?(Array) }
      else
        []
      end
    end

    def signed_turns(headings)
      headings.each_cons(2).map do |from, to|
        delta = (to - from) % 360
        delta > 180 ? delta - 360 : delta
      end
    end

    def radius_nm(samples)
      lat = samples.map { |sample| number_value(sample["lat"]) }.sum / samples.length.to_f
      lon = samples.map { |sample| number_value(sample["lon"]) }.sum / samples.length.to_f
      samples.map { |sample| distance_nm(lat, lon, number_value(sample["lat"]), number_value(sample["lon"])) }.max || 0.0
    end

    def distance_nm(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180.0
      earth_radius_nm = 3440.065
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      a = Math.sin(dlat / 2)**2 +
          Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
      2 * earth_radius_nm * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    def median(values)
      sorted = values.sort
      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def rounded(value)
      value.round(2)
    end

    def integer(value)
      return value if value.is_a?(Integer)

      nil
    end

    def number?(value)
      value.is_a?(Numeric) && !value.is_a?(Complex)
    end

    def number_value(value)
      number?(value) ? value : nil
    end

    def present_string?(value)
      value.is_a?(String) && !value.empty?
    end
  end
end

def detect(frame, buffer)
  FlightWatch::AnomalyRules.detect(frame, buffer)
end

if __FILE__ == $PROGRAM_NAME
  require "json"

  input = ARGF.read
  payload = JSON.parse(input)
  frame = payload.fetch("frame")
  buffer = payload.fetch("buffer", [])
  puts JSON.pretty_generate(detect(frame, buffer))
end
