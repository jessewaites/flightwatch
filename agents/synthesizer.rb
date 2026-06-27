# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "../contracts/validate"

module FlightWatch
  class Synthesizer
    AIRPORTS = {
      "KBOS" => { lat: 42.3656, lon: -71.0096 }
    }.freeze
    SKILL_PATH = File.expand_path("../skills/airspace-situation/SKILL.md", __dir__)

    CLUSTER_MIN_FLAGS = 3
    CLUSTER_RADIUS_NM = 10.0
    CLUSTER_WINDOW_S = 120
    LOOP_SLEEP_S = 5

    GROUND_STOP_RULES = %w[holding_pattern going_dark altitude_outlier].freeze
    WEATHER_DIVERSION_RULES = %w[holding_pattern rapid_descent altitude_outlier going_dark].freeze
    RUNWAY_CLOSURE_RULES = %w[holding_pattern rapid_descent going_dark].freeze
    RELATED_RULE_SETS = {
      "ground_stop" => GROUND_STOP_RULES,
      "weather_diversion" => WEATHER_DIVERSION_RULES,
      "runway_closure" => RUNWAY_CLOSURE_RULES
    }.freeze

    MODEL_PROMPT = <<~PROMPT.freeze
      You are the Synthesizer in a multi-agent airspace monitor over Boston. Deterministic code has already
      clustered related flags by area, airport, and time window. You receive one cluster with member aircraft,
      their flags, the Investigator's verdicts, and optional Boston weather context. Name the emergent situation
      it represents and explain it in one line.

      Use weather_context only as background. Mention it briefly when it helps explain the cluster, but do not
      invent weather causes beyond the supplied context.

      Respond with ONLY this JSON:
      {"kind":"ground_stop|weather_diversion|runway_closure","airport":"KBOS","summary":"one plain line"}
    PROMPT

    attr_reader :workspace_dir, :model

    def initialize(workspace_dir: File.expand_path("../workspace", __dir__), model: nil, use_model: true, once: false)
      @workspace_dir = workspace_dir
      @model = model
      @use_model = use_model
      @once = once
      @written_ids = {}
    end

    def run
      loop do
        safely_run_once
        break if @once

        sleep LOOP_SLEEP_S
      end
    end

    def safely_run_once
      run_once
    rescue StandardError => e
      observe("synthesizer_error", error: "#{e.class}: #{e.message}")
      nil
    end

    def run_once
      FileUtils.mkdir_p(situations_dir)

      # If the situations dir was cleared out (e.g. a mode switch reset the bus), forget what we've
      # already written so the new run's situations fire again instead of being deduped away.
      @written_ids = {} if @written_ids.any? && Dir[File.join(situations_dir, "*.json")].empty?

      flags = load_json_files(flags_dir, :flag)
      verdicts = verdicts_by_aircraft(load_json_files(verdicts_dir, :verdict))
      clusters = build_clusters(flags)
      written = []

      clusters.each do |cluster|
        situation = interpret_cluster(cluster, verdicts)
        next if situation_exists?(situation["id"])

        write_situation(situation)
        written << situation
      end

      written
    end

    def build_clusters(flags)
      eligible_flags = flags.select { |flag| flag["lat"] && flag["lon"] && flag["ts"] }
      clusters = []

      AIRPORTS.each do |airport, position|
        airport_flags = eligible_flags.select do |flag|
          distance_nm(flag["lat"], flag["lon"], position[:lat], position[:lon]) <= CLUSTER_RADIUS_NM
        end

        RELATED_RULE_SETS.each do |cluster_kind, rules|
          related = airport_flags.select { |flag| rules.include?(flag["rule"]) }.sort_by { |flag| [flag["ts"], flag["icao24"]] }
          related.each_with_index do |anchor, index|
            window = related[index..-1].select { |flag| (flag["ts"] - anchor["ts"]).abs <= CLUSTER_WINDOW_S }
            members = unique_aircraft(window)
            next if members.length < CLUSTER_MIN_FLAGS

            clusters << {
              kind_hint: cluster_kind,
              airport: airport,
              flags: members,
              ts: members.map { |flag| flag["ts"] }.max
            }
            break
          end
        end
      end

      dedupe_clusters(clusters)
    end

    def interpret_cluster(cluster, verdicts)
      weather_context = load_weather_context(cluster[:airport])
      model_result = @use_model ? call_model(cluster, verdicts, weather_context) : nil
      kind = valid_kind(model_result && model_result["kind"]) || cluster[:kind_hint] || heuristic_kind(cluster, verdicts)
      airport = model_result && model_result["airport"].to_s.strip != "" ? model_result["airport"].to_s.strip : cluster[:airport]
      icao24s = cluster[:flags].map { |flag| flag["icao24"] }.uniq.sort
      ts = cluster[:ts].to_i

      summary = model_result && model_result["summary"].to_s.strip
      summary = nil if summary == ""
      summary ||= fallback_summary(kind, airport, cluster, verdicts, weather_context)

      {
        "id" => situation_id(airport, kind, ts),
        "ts" => ts,
        "kind" => kind,
        "airport" => airport,
        "icao24s" => icao24s,
        "summary" => summary
      }
    end

    private

    def flags_dir
      File.join(workspace_dir, "flags")
    end

    def verdicts_dir
      File.join(workspace_dir, "verdicts")
    end

    def weather_dir
      File.join(workspace_dir, "weather")
    end

    def situations_dir
      File.join(workspace_dir, "situations")
    end

    def observe_dir
      File.join(workspace_dir, "observe")
    end

    def load_json_files(dir, kind)
      return [] unless Dir.exist?(dir)

      Dir[File.join(dir, "*.json")].sort.each_with_object([]) do |path, objects|
        obj = JSON.parse(File.read(path))
        ok, errors = Contracts.validate(kind, obj)
        unless ok
          observe("invalid_#{kind}", path: path, errors: errors)
          next
        end
        objects << obj
      rescue JSON::ParserError, Errno::ENOENT => e
        observe("read_skip", path: path, error: "#{e.class}: #{e.message}")
      end
    end

    def load_weather_context(airport)
      path = File.join(weather_dir, "#{airport.to_s.downcase}.json")
      return nil unless File.exist?(path)

      context = JSON.parse(File.read(path))
      return nil unless context.is_a?(Hash) && context["summary"].to_s.strip != ""

      context
    rescue JSON::ParserError, Errno::ENOENT => e
      observe("weather_context_skip", path: path, error: "#{e.class}: #{e.message}")
      nil
    end

    def verdicts_by_aircraft(verdicts)
      verdicts.each_with_object({}) do |verdict, index|
        index[[verdict["icao24"], verdict["flag_ts"]]] = verdict
      end
    end

    def unique_aircraft(flags)
      seen = {}
      flags.each_with_object([]) do |flag, list|
        next if seen[flag["icao24"]]

        seen[flag["icao24"]] = true
        list << flag
      end
    end

    def dedupe_clusters(clusters)
      seen = {}
      clusters.sort_by { |cluster| [-cluster[:flags].length, cluster[:ts], cluster[:kind_hint]] }.each_with_object([]) do |cluster, list|
        key = [cluster[:airport], cluster[:flags].map { |flag| flag["icao24"] }.sort.join(","), cluster[:ts]]
        next if seen[key]

        seen[key] = true
        list << cluster
      end
    end

    def distance_nm(lat1, lon1, lat2, lon2)
      earth_radius_nm = 3440.065
      rad = Math::PI / 180.0
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      a = Math.sin(dlat / 2.0)**2 +
          Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2.0)**2
      2.0 * earth_radius_nm * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))
    end

    def call_model(cluster, verdicts, weather_context)
      llm = model || default_model
      return nil unless llm

      content = JSON.pretty_generate(cluster_payload(cluster, verdicts, weather_context))
      prompt = [skill_text, MODEL_PROMPT].compact.join("\n\n")
      response = if llm.respond_to?(:ask)
                   llm.ask("#{prompt}\n\nCluster:\n#{content}")
                 elsif llm.respond_to?(:chat)
                   llm.chat.with_instructions(MODEL_PROMPT).ask(content)
                 end
      parse_model_json(response)
    rescue StandardError => e
      observe("model_skip", error: "#{e.class}: #{e.message}")
      nil
    end

    def default_model
      require "ruby_llm"
      RubyLLM.chat(model: ENV.fetch("SYNTHESIZER_MODEL", "claude-sonnet-4-20250514"))
    rescue LoadError, StandardError => e
      observe("model_unavailable", error: "#{e.class}: #{e.message}")
      nil
    end

    def skill_text
      File.exist?(SKILL_PATH) ? File.read(SKILL_PATH) : nil
    rescue StandardError => e
      observe("skill_read_skip", error: "#{e.class}: #{e.message}")
      nil
    end

    def cluster_payload(cluster, verdicts, weather_context)
      {
        airport: cluster[:airport],
        kind_hint: cluster[:kind_hint],
        window_s: CLUSTER_WINDOW_S,
        radius_nm: CLUSTER_RADIUS_NM,
        flags: cluster[:flags],
        verdicts: cluster[:flags].map { |flag| verdicts[[flag["icao24"], flag["ts"]]] }.compact
      }.tap do |payload|
        payload[:weather_context] = weather_context if weather_context
      end
    end

    def parse_model_json(response)
      text = if response.respond_to?(:content)
               response.content
             else
               response.to_s
             end
      JSON.parse(text)
    rescue JSON::ParserError
      match = text && text.match(/\{.*\}/m)
      match ? JSON.parse(match[0]) : nil
    end

    def valid_kind(kind)
      Contracts::SITUATION_KINDS.include?(kind) ? kind : nil
    end

    def heuristic_kind(cluster, verdicts)
      rules = cluster[:flags].map { |flag| flag["rule"] }
      summaries = cluster[:flags].map { |flag| verdicts[[flag["icao24"], flag["ts"]]] }.compact.map { |verdict| verdict["summary"].to_s.downcase }
      text = summaries.join(" ")

      return "runway_closure" if text.include?("runway") || text.include?("closure")
      return "weather_diversion" if text.include?("weather") || text.include?("storm") || text.include?("wind")
      return "ground_stop" if rules.count("holding_pattern") >= CLUSTER_MIN_FLAGS

      "ground_stop"
    end

    def fallback_summary(kind, airport, cluster, verdicts, weather_context = nil)
      rule_counts = cluster[:flags].each_with_object(Hash.new(0)) { |flag, counts| counts[flag["rule"]] += 1 }
      verdict_count = cluster[:flags].count { |flag| verdicts.key?([flag["icao24"], flag["ts"]]) }
      count_text = rule_counts.sort.map { |rule, count| "#{count} #{rule.tr("_", " ")}" }.join(" + ")
      verdict_text = verdict_count.positive? ? " with #{verdict_count} investigator verdicts" : ""
      weather_text = weather_context && weather_context["summary"].to_s.strip
      weather_clause = weather_text && weather_text != "" ? " Weather context: #{weather_text}" : ""

      case kind
      when "weather_diversion"
        "#{count_text} near #{airport} inside a two-minute window#{verdict_text}; pattern is consistent with weather diversion pressure.#{weather_clause}"
      when "runway_closure"
        "#{count_text} near #{airport} inside a two-minute window#{verdict_text}; pattern is consistent with a runway closure.#{weather_clause}"
      else
        "#{count_text} near #{airport} inside a two-minute window#{verdict_text}; pattern is consistent with a possible ground stop.#{weather_clause}"
      end
    end

    def situation_id(airport, kind, ts)
      "#{airport.downcase}-#{kind.tr("_", "-")}-#{ts}"
    end

    def situation_exists?(id)
      return true if @written_ids[id]

      File.exist?(File.join(situations_dir, "#{id}.json"))
    end

    def write_situation(situation)
      ok, errors = Contracts.validate(:situation, situation)
      raise "invalid situation: #{errors.join(', ')}" unless ok

      FileUtils.mkdir_p(situations_dir)
      final_path = File.join(situations_dir, "#{situation["id"]}.json")
      tmp_path = "#{final_path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp_path, JSON.pretty_generate(situation) + "\n")
      File.rename(tmp_path, final_path)
      @written_ids[situation["id"]] = true
      observe("situation_written", id: situation["id"], kind: situation["kind"], airport: situation["airport"], count: situation["icao24s"].length)
    ensure
      FileUtils.rm_f(tmp_path) if tmp_path && File.exist?(tmp_path)
    end

    def observe(event, attrs = {})
      FileUtils.mkdir_p(observe_dir)
      line = { ts: Time.now.to_i, agent: "synthesizer", event: event }.merge(attrs)
      File.open(File.join(observe_dir, "run.jsonl"), "a") { |f| f.puts(JSON.generate(line)) }
    rescue StandardError
      nil
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require "optparse"

  options = {
    workspace_dir: File.expand_path("../workspace", __dir__),
    once: false,
    use_model: true
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby agents/synthesizer.rb [--workspace DIR] [--once] [--no-skill] [--offline]"
    opts.on("--workspace DIR", "Workspace file bus root") { |dir| options[:workspace_dir] = dir }
    opts.on("--once", "Run one synthesis pass and exit") { options[:once] = true }
    opts.on("--no-skill", "Run without the airspace-situation skill prompt/model") { options[:use_model] = false }
    opts.on("--offline", "Avoid frontier calls; deterministic fallback only") { options[:use_model] = false }
  end.parse!

  FlightWatch::Synthesizer.new(**options).run
end
