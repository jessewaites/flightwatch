require "fileutils"
require "json"

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

      def read_collection(kind)
        files = json_files(path.join(kind))
        files = json_files(fixture_path.join(kind)) if files.empty?

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
        frame = read_json(latest_frame_path) || read_json(sample_frame_path) || { "ts" => Time.now.to_i, "aircraft" => [] }
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

      def anomaly_for(flag_or_verdict)
        icao24 = flag_or_verdict["icao24"]
        flag_ts = flag_or_verdict["ts"] || flag_or_verdict["flag_ts"]
        flag = read_collection("flags").find { |item| item["icao24"] == icao24 && item["ts"].to_i == flag_ts.to_i }
        verdict = read_collection("verdicts").find { |item| item["icao24"] == icao24 && item["flag_ts"].to_i == flag_ts.to_i }

        build_anomaly(flag || { "icao24" => icao24, "ts" => flag_ts }, verdict)
      end

      def routing_rows(verdicts = read_collection("verdicts"), situations = read_collection("situations"))
        investigator_tokens = verdicts.size * 1_700
        synthesizer_tokens = situations.size * 2_200

        [
          row("Watcher", "granite4:micro", "Ollama local", 0, 0.0, "35 ms"),
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
        JSON.parse(File.read(file))
      rescue Errno::ENOENT, JSON::ParserError
        nil
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

      def row(agent, model, route, tokens, cost, latency)
        { agent: agent, model: model, route: route, tokens: tokens, cost: cost, latency: latency }
      end
    end
  end
end
