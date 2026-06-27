# frozen_string_literal: true

require "json"
require "optparse"
require "fileutils"
require "shellwords"
require "time"

FLIGHTWATCH_ROOT = File.expand_path("..", __dir__)
DETECTOR_PATH = File.join(FLIGHTWATCH_ROOT, "skills/flight-anomaly-rules/scripts/detect.rb")
SKILL_PATH = File.join(FLIGHTWATCH_ROOT, "skills/flight-anomaly-rules/SKILL.md")
CONTRACTS_PATH = File.join(FLIGHTWATCH_ROOT, "contracts/validate.rb")

load DETECTOR_PATH
require CONTRACTS_PATH

module FlightWatch
  class Watcher
    EMERGENCY_ORDER = { "7700" => 0, "7500" => 1, "7600" => 2 }.freeze
    TIER2_RULE_ORDER = {
      "rapid_descent" => 0,
      "going_dark" => 1,
      "altitude_outlier" => 2,
      "holding_pattern" => 3
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the Watcher in a multi-agent airspace monitor over Boston. Each tick you receive one frame of all aircraft.
      A deterministic tool has already found rule-based candidates. Your ONLY job is TRIAGE PRIORITIZATION.

      Tier 1 is handled in code, not by you: emergency squawks always rank first, in order 7700 > 7500 > 7600.
      Your job is Tier 2: order remaining flags by:
      1. anomaly severity, with rapid_descent and going_dark before holding_pattern
      2. proximity to risk, with populated or near-airport positions before open water
      3. freshness, with new flags before stale flags
      4. detection confidence, with clean trips before marginal evidence

      Respond with ONLY this JSON, no prose and no markdown fences:
      {"order":["a35e3d","a4996b"]}
    PROMPT

    def initialize(options)
      @workspace = File.expand_path(options.fetch(:workspace))
      @tracks_dir = File.expand_path(options.fetch(:tracks_dir))
      @frame_path = options[:frame_path]
      @frames_path = options[:frames_path]
      @offline = options.fetch(:offline)
      @once = options.fetch(:once)
      @poll_interval = options.fetch(:poll_interval)
      @max_buffer = options.fetch(:max_buffer)
      @no_skill = options.fetch(:no_skill)
      @model = options.fetch(:model)
      @ollama_base = options.fetch(:ollama_base)
      @buffer = []
      @seen_track_paths = {}
    end

    def run
      prepare_workspace

      if @frame_path
        process_frame(read_json_file(@frame_path))
      elsif @frames_path
        read_frames(@frames_path).each { |frame| process_frame(frame) }
      elsif @offline
        process_frame(read_json_file(File.join(FLIGHTWATCH_ROOT, "contracts/fixtures/frame.sample.json")))
      else
        loop_tracks
      end

      print_routing_summary
    end

    private

    def prepare_workspace
      FileUtils.mkdir_p(flags_dir)
      FileUtils.mkdir_p(observe_dir)
    end

    def loop_tracks
      loop do
        paths = Dir[File.join(@tracks_dir, "*.json")].sort
        paths.each do |path|
          next if @seen_track_paths[path]

          process_frame(read_json_file(path))
          @seen_track_paths[path] = true
        rescue JSON::ParserError, Errno::ENOENT => e
          warn "watcher skipped malformed frame file #{path}: #{e.message}"
        end

        break if @once

        sleep @poll_interval
      end
    end

    def process_frame(frame)
      unless frame.is_a?(Hash)
        warn "watcher skipped non-object frame"
        return
      end

      flags = detect(frame, @buffer)
      ranked = prioritize(flags)
      ranked.each { |flag| write_flag(flag) }
      append_observation(frame, ranked)
      remember_frame(frame)
    rescue StandardError => e
      warn "watcher skipped malformed frame: #{e.class}: #{e.message}"
    end

    def remember_frame(frame)
      return unless frame.is_a?(Hash) && frame["aircraft"].is_a?(Array)

      @buffer << frame
      @buffer.shift while @buffer.length > @max_buffer
    end

    def prioritize(flags)
      emergency, tier2 = flags.partition { |flag| flag["rule"] == "emergency_squawk" }
      emergency.sort_by! { |flag| [EMERGENCY_ORDER.fetch(flag.dig("evidence", "squawk"), 99), flag["icao24"]] }

      tier2 = if tier2.length > 1 && !@no_skill
                model_rank_tier2(tier2) || deterministic_rank_tier2(tier2)
              else
                deterministic_rank_tier2(tier2)
              end
      emergency + tier2
    end

    def deterministic_rank_tier2(flags)
      flags.sort_by do |flag|
        [
          TIER2_RULE_ORDER.fetch(flag["rule"], 99),
          severity_rank(flag["severity"]),
          -freshness_score(flag),
          flag["icao24"]
        ]
      end
    end

    def model_rank_tier2(flags)
      ids = flags.map { |flag| flag.fetch("icao24") }
      order = parse_model_order(ask_model(flags))
      return nil unless order.any?

      rank = order.each_with_index.to_h
      flags.sort_by { |flag| [rank.fetch(flag["icao24"], ids.length), ids.index(flag["icao24"]) || ids.length] }
    rescue StandardError => e
      warn "watcher model triage failed; using deterministic tier-2 order: #{e.message}"
      nil
    end

    def ask_model(flags)
      require "ruby_llm"

      RubyLLM.configure do |config|
        config.openai_api_key = "ollama"
        config.openai_api_base = @ollama_base
        config.openai_use_system_role = true if config.respond_to?(:openai_use_system_role=)
      end

      prompt = +"#{SYSTEM_PROMPT}\n"
      prompt << "\nLoaded skill:\n#{File.read(SKILL_PATH)}\n" unless @no_skill
      prompt << "\nRank these Tier-2 flags and return exactly {\"order\":[\"icao24\", ...]}:\n"
      prompt << JSON.pretty_generate(flags)

      chat = RubyLLM.chat(model: @model, provider: :openai, assume_model_exists: true)
                   .with_temperature(0)
                   .with_params(response_format: { type: "json_object" })
      response = chat.ask(prompt)
      response.respond_to?(:content) ? response.content : response.to_s
    end

    def parse_model_order(text)
      stripped = strip_markdown_fences(text.to_s.strip)
      parsed = JSON.parse(stripped)
      entries = parsed.is_a?(Hash) ? parsed["order"] : parsed
      Array(entries).map do |entry|
        case entry
        when String then entry
        when Hash then entry["icao24"] || entry[:icao24] || entry["id"] || entry[:id]
        end
      end.compact
    rescue JSON::ParserError
      []
    end

    def strip_markdown_fences(text)
      text.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
    end

    def severity_rank(severity)
      { "high" => 0, "medium" => 1, "low" => 2 }.fetch(severity, 9)
    end

    def freshness_score(flag)
      Integer(flag["ts"])
    rescue StandardError
      0
    end

    def write_flag(flag)
      ok, errors = FlightWatch::Contracts.validate(:flag, flag)
      raise "flag contract invalid: #{errors.join(', ')}" unless ok

      path = File.join(flags_dir, "#{flag.fetch("icao24")}-#{flag.fetch("ts")}.json")
      tmp = "#{path}.tmp-#{$$}"
      File.write(tmp, "#{JSON.pretty_generate(flag)}\n")
      File.rename(tmp, path)
    end

    def append_observation(frame, flags)
      line = {
        "ts" => Time.now.to_i,
        "agent" => "watcher",
        "model" => @no_skill ? "none (--no-skill)" : @model,
        "route" => @no_skill ? "deterministic" : "detector+ruby_llm_tier2",
        "frame_ts" => frame["ts"],
        "flags" => flags.map { |flag| flag["icao24"] },
        "tokens" => 0,
        "cost_usd" => 0.0,
        "latency_ms" => nil
      }
      File.open(File.join(observe_dir, "run.jsonl"), "a") { |file| file.puts(JSON.generate(line)) }
    end

    def print_routing_summary
      puts "agent\tmodel\troute\ttokens\tcost\tlatency"
      puts "watcher\t#{@no_skill ? "none (--no-skill)" : @model}\t#{@no_skill ? "deterministic" : "detector+ruby_llm_tier2"}\t0\t$0.00\tlocal"
      puts "TOTAL\t-\t-\t0\t$0.00\t-"
    end

    def read_frames(path)
      text = File.read(path)
      if File.extname(path) == ".jsonl"
        text.each_line.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
      else
        parsed = JSON.parse(text)
        parsed.is_a?(Array) ? parsed : [parsed]
      end
    end

    def read_json_file(path)
      JSON.parse(File.read(path))
    end

    def flags_dir
      File.join(@workspace, "flags")
    end

    def observe_dir
      File.join(@workspace, "observe")
    end
  end
end

options = {
  workspace: File.join(FLIGHTWATCH_ROOT, "workspace"),
  tracks_dir: File.join(FLIGHTWATCH_ROOT, "workspace/tracks"),
  frame_path: nil,
  frames_path: nil,
  offline: false,
  once: false,
  no_skill: false,
  poll_interval: 1.0,
  max_buffer: 12,
  model: "granite4:micro",
  ollama_base: "http://localhost:11434/v1"
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby agents/watcher.rb [options]"
  parser.on("--workspace PATH", "Workspace file-bus root") { |value| options[:workspace] = value }
  parser.on("--tracks PATH", "Directory to poll for normalized frame JSON files") { |value| options[:tracks_dir] = value }
  parser.on("--frame PATH", "Process one normalized frame JSON file") { |value| options[:frame_path] = value }
  parser.on("--frames PATH", "Process normalized frame JSON or JSONL file") { |value| options[:frames_path] = value }
  parser.on("--offline", "Process bundled contract fixture") { options[:offline] = true }
  parser.on("--once", "Process available input once and exit") { options[:once] = true }
  parser.on("--no-skill", "Do not load SKILL.md into the model prompt; detect.rb still runs") { options[:no_skill] = true }
  parser.on("--poll SECONDS", Float, "Track polling interval") { |value| options[:poll_interval] = value }
  parser.on("--model MODEL", "Ollama model name") { |value| options[:model] = value }
  parser.on("--ollama-base URL", "OpenAI-compatible Ollama base URL") { |value| options[:ollama_base] = value }
end.parse!

FlightWatch::Watcher.new(options).run if __FILE__ == $PROGRAM_NAME
