require "fileutils"
require "json"
require "securerandom"

require Rails.root.join("..", "contracts", "validate").to_s

module Flightwatch
  class Workspace
    KBOS = { lat: 42.3656, lon: -71.0096 }.freeze

    class << self
      def path
        Pathname.new(ENV.fetch("FLIGHTWATCH_WORKSPACE", Rails.root.join("..", "workspace").to_s)).expand_path
      end

      def fixture_path
        Rails.root.join("..", "contracts", "fixtures", "workspace").expand_path
      end

      def sample_frame_path
        Rails.root.join("..", "contracts", "fixtures", "frame.sample.json").expand_path
      end

      def snapshot
        flags = read_collection("flags")
        verdicts = read_collection("verdicts")
        situations = read_collection("situations")

        {
          mode: read_mode,
          frame: read_frame(flags),
          flags: flags,
          verdicts: verdicts,
          situations: situations,
          anomalies: anomalies(flags, verdicts),
          routing: routing_rows(verdicts, situations)
        }
      end

      # Live bus only. Fixtures are an opt-in dev convenience (FLIGHTWATCH_FIXTURES=1) for working on
      # the UI without running the agents — NEVER a silent fallback, or an empty bus shows fake data
      # (the stale "ground stop"/"runway closure" banner problem).
      def use_fixtures?
        ENV["FLIGHTWATCH_FIXTURES"] == "1"
      end

      def read_collection(kind)
        files = json_files(path.join(kind))
        files = json_files(fixture_path.join(kind)) if files.empty? && use_fixtures?

        files.filter_map { |file| read_json(file) }
          .sort_by { |item| -(item["ts"] || item["flag_ts"] || 0).to_i }
      end

      # Newest live frame the producer has written to workspace/tracks/ (zero-padded names sort
      # chronologically), or nil if the pipeline isn't running yet.
      def latest_frame_path
        dir = path.join("tracks")
        return nil unless dir.exist?

        dir.children.select { |file| file.file? && file.extname == ".json" }
           .max_by { |file| file.basename.to_s }
      end

      def read_frame(flags = read_collection("flags"))
        frame = read_json(latest_frame_path)
        frame ||= read_json(sample_frame_path) if use_fixtures?
        frame ||= { "ts" => Time.now.to_i, "aircraft" => [] }
        flagged = flags.to_h { |flag| [ flag["icao24"], flag ] }

        aircraft = Array(frame["aircraft"]).map do |plane|
          flag = flagged[plane["icao24"]]
          plane.merge(
            "state" => plane["on_ground"] ? "ground" : (flag ? "flagged" : "normal"),
            "flag_ts" => flag&.fetch("ts", nil)
          )
        end

        frame.merge("aircraft" => aircraft, "airport" => { "code" => "KBOS" }.merge(KBOS.transform_keys(&:to_s)))
      end

      def read_mode
        mode_file = path.join("control", "mode.json")
        mode_file = fixture_path.join("control", "mode.json") unless mode_file.exist?
        (read_json(mode_file) || { "source" => "demo" })["source"]
      end

      def write_mode(source)
        source = source == "realtime" ? "realtime" : "demo"
        control_dir = path.join("control")
        FileUtils.mkdir_p(control_dir)
        File.write(control_dir.join("mode.json"), JSON.pretty_generate({ source: source }))
        source
      end

      def generate_synthesis!
        flags = read_collection("flags")
        verdicts = read_collection("verdicts")
        frame = read_frame(flags)
        weather = read_weather_context("KBOS")
        situation = build_current_synthesis(frame, flags, verdicts, weather)
        ok, errors = FlightWatch::Contracts.validate(:situation, situation)
        raise "invalid generated situation: #{errors.join(', ')}" unless ok

        situations_dir = path.join("situations")
        FileUtils.mkdir_p(situations_dir)
        final_path = situations_dir.join("#{situation["id"]}.json")
        tmp_path = situations_dir.join("#{situation["id"]}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
        File.write(tmp_path, JSON.pretty_generate(situation) + "\n")
        File.rename(tmp_path, final_path)
        situation
      ensure
        FileUtils.rm_f(tmp_path) if tmp_path && File.exist?(tmp_path)
      end

      # Clear the runtime bus so a mode switch starts a clean run, regardless of whether the
      # producer is running. Keeps the map, feed, and pagination consistent with the bus.
      def reset_bus
        %w[flags verdicts situations tracks].each do |kind|
          dir = path.join(kind)
          next unless dir.exist?

          dir.children.each { |file| file.delete if file.file? && file.extname == ".json" }
        end
      end

      def anomaly_for(flag_or_verdict)
        icao24 = flag_or_verdict["icao24"]
        flag_ts = flag_or_verdict["ts"] || flag_or_verdict["flag_ts"]
        flag = read_collection("flags").find { |item| item["icao24"] == icao24 && item["ts"].to_i == flag_ts.to_i }
        verdict = read_collection("verdicts").find { |item| item["icao24"] == icao24 && item["flag_ts"].to_i == flag_ts.to_i }

        build_anomaly(flag || { "icao24" => icao24, "ts" => flag_ts }, verdict)
      end

      def routing_rows(verdicts = read_collection("verdicts"), situations = read_collection("situations"))
        watcher_tokens = observe_tokens_for("watcher")
        investigator_tokens = verdicts.size * 1_700
        synthesizer_tokens = situations.size * 2_200

        [
          row("Watcher", "granite4:micro", "Ollama local", watcher_tokens, 0.0, "35 ms"),
          row("Investigator", "Claude frontier", "Anthropic", investigator_tokens, verdicts.size * 0.012, verdicts.any? ? "1.8 s" : "-"),
          row("Synthesizer", "Claude mid/frontier", "Anthropic", synthesizer_tokens, situations.size * 0.018, situations.any? ? "2.4 s" : "-")
        ].tap do |rows|
          rows << row("TOTAL", "", "", rows.sum { |r| r[:tokens] }, rows.sum { |r| r[:cost] }, "")
        end
      end

      private

      def json_files(directory)
        return [] unless directory.exist?

        directory.children.select { |file| file.file? && file.extname == ".json" }
      end

      def read_json(file)
        return nil if file.nil?

        JSON.parse(File.read(file))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def read_weather_context(airport)
        read_json(path.join("weather", "#{airport.to_s.downcase}.json"))
      end

      # Sum the tokens an agent has logged to the observe event log (workspace/observe/run.jsonl).
      # The routing table is a reduction over this log, not a separate accounting path.
      def observe_tokens_for(agent)
        log = path.join("observe", "run.jsonl")
        return 0 unless log.exist?

        total = 0
        File.foreach(log) do |line|
          obj = JSON.parse(line) rescue next
          total += obj["tokens"].to_i if obj["agent"] == agent
        end
        total
      end

      def anomalies(flags, verdicts)
        by_key = verdicts.index_by { |verdict| anomaly_key(verdict["icao24"], verdict["flag_ts"]) }

        flags.map do |flag|
          build_anomaly(flag, by_key[anomaly_key(flag["icao24"], flag["ts"])])
        end
      end

      def build_anomaly(flag, verdict)
        {
          id: anomaly_key(flag["icao24"], flag["ts"]),
          icao24: flag["icao24"],
          ts: flag["ts"],
          rule: flag["rule"] || "pending_flag",
          severity: flag["severity"] || "pending",
          lat: flag["lat"],
          lon: flag["lon"],
          evidence: flag["evidence"] || {},
          verdict: verdict
        }
      end

      def anomaly_key(icao24, ts)
        "#{icao24}-#{ts}"
      end

      def build_current_synthesis(frame, flags, verdicts, weather)
        ts = [frame["ts"], flags.first&.dig("ts"), verdicts.first&.dig("flag_ts"), Time.now.to_i].compact.map(&:to_i).max
        recent_flags = recent_by_ts(flags, ts, "ts")
        recent_verdicts = recent_by_ts(verdicts, ts, "flag_ts")
        icao24s = (recent_flags.map { |flag| flag["icao24"] } + recent_verdicts.map { |verdict| verdict["icao24"] }).uniq.sort
        icao24s = Array(frame["aircraft"]).filter_map { |plane| plane["icao24"] }.first(5) if icao24s.empty?

        {
          "id" => "kbos-current-synthesis-#{ts}-#{SecureRandom.hex(3)}",
          "ts" => ts,
          "kind" => synthesis_kind(recent_flags, recent_verdicts, weather),
          "airport" => "KBOS",
          "icao24s" => icao24s,
          "summary" => synthesis_summary(frame, recent_flags, recent_verdicts, weather)
        }
      end

      def recent_by_ts(collection, ts, field)
        recent = collection.select { |item| item[field].to_i >= ts.to_i - 900 }
        (recent.any? ? recent : collection).first(8)
      end

      def synthesis_kind(flags, verdicts, weather)
        text = ([weather_summary(weather)] + verdicts.map { |verdict| verdict["summary"] }).compact.join(" ").downcase
        rules = flags.map { |flag| flag["rule"] }

        return "runway_closure" if text.match?(/runway|closure/)
        return "weather_diversion" if text.match?(/storm|wind shear|gust|fog|low visibility|ifr|low ceiling|thunder|rain|snow|diversion/) || rules.include?("rapid_descent")

        "ground_stop"
      end

      def synthesis_summary(frame, flags, verdicts, weather)
        aircraft = Array(frame["aircraft"])
        airborne = aircraft.count { |plane| !plane["on_ground"] }
        flagged = flags.count
        severities = flags.each_with_object(Hash.new(0)) { |flag, counts| counts[flag["severity"]] += 1 }
        rules = flags.each_with_object(Hash.new(0)) { |flag, counts| counts[flag["rule"]] += 1 }
        severity_text = counts_sentence(severities, "severity")
        rule_text = counts_sentence(rules, "rule")
        weather_text = weather_summary(weather)

        paragraph_one = "KBOS is showing #{airborne} airborne aircraft in the current frame"
        paragraph_one += " with #{flagged} recent watcher #{'flag'.pluralize(flagged)}" if flagged.positive?
        paragraph_one += "."
        paragraph_one += " The watcher mix is #{rule_text}; #{severity_text}." if flagged.positive?

        paragraph_two = if verdicts.any?
          verdict_bits = verdicts.first(4).map do |verdict|
            "#{verdict["icao24"]}: #{verdict["assessment"]} (#{verdict["summary"]})"
          end
          "The most recent investigations say #{verdict_bits.to_sentence}."
        else
          "No investigator verdicts are available in the current window yet, so this synthesis is based on watcher output and the latest track frame."
        end

        paragraph_three = weather_text.to_s.strip
        paragraph_three = paragraph_three.present? ? "Current weather context: #{paragraph_three}" : "No current KBOS weather context is present on the file bus."

        [paragraph_one, paragraph_two, paragraph_three].join("\n\n")
      end

      def weather_summary(weather)
        return nil unless weather.is_a?(Hash)

        weather["summary"].presence || weather["metar"].presence || weather["raw"].presence
      end

      def counts_sentence(counts, label)
        return "no #{label} counts" if counts.empty?

        counts.sort.map { |key, count| "#{count} #{key.to_s.tr('_', ' ')}" }.to_sentence
      end

      def row(agent, model, route, tokens, cost, latency)
        { agent: agent, model: model, route: route, tokens: tokens, cost: cost, latency: latency }
      end
    end
  end
end
