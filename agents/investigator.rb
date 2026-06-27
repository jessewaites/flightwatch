# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "time"
require_relative "../contracts/validate"
require_relative "../enrichment/flightwatch_enrichment"

module FlightWatch
  module Investigator
    ROOT = File.expand_path("..", __dir__)
    SKILL_PATH = File.join(ROOT, "skills", "flight-investigation", "SKILL.md")
    SKILL_REFERENCES = File.join(ROOT, "skills", "flight-investigation", "references", "*.md")

    SYSTEM_PROMPT = <<~PROMPT
      You are the Investigator in a multi-agent airspace monitor over Boston. You receive ONE flagged
      aircraft with its rule, evidence, and enrichment. Judge whether this flag is benign, a concern, or
      a real emergency using aviation convention, not alarm.

      Respond with ONLY this JSON:
      {"assessment":"benign|concern|emergency","confidence":0.0,"summary":"one plain-language line"}
    PROMPT

    class Runner
      def initialize(options = {})
        @workspace = File.expand_path(options.fetch(:workspace, File.join(ROOT, "workspace")))
        @offline = options.fetch(:offline, false)
        @use_skill = options.fetch(:use_skill, true)
        @once = options.fetch(:once, false)
        @poll_interval = options.fetch(:poll_interval, 1.0).to_f
      end

      def run
        ensure_workspace_dirs
        loop do
          processed = process_next
          break if @once

          sleep(@poll_interval) unless processed
        end
      rescue Interrupt
        warn "investigator: stopped"
      end

      def process_next
        path = next_flag_path
        return false unless path

        started = Time.now
        flag = read_flag(path)
        enrichment = Enrichment.for_flag(flag, offline: @offline)
        result = judge(flag, enrichment)
        verdict = build_verdict(flag, enrichment, result)
        write_verdict(flag, verdict)
        latency_ms = ((Time.now - started) * 1000).round
        record_observation(flag, result, latency_ms)
        print_routing_table(result, latency_ms)
        true
      rescue StandardError => e
        warn "investigator error: #{e.class}: #{e.message}"
        write_failure_verdict(path, e) if path
        true
      end

      private

      def ensure_workspace_dirs
        %w[flags verdicts observe].each do |dir|
          FileUtils.mkdir_p(File.join(@workspace, dir))
        end
      end

      def next_flag_path
        Dir[File.join(@workspace, "flags", "*.json")].reject do |flag_path|
          File.exist?(verdict_path_for_filename(File.basename(flag_path)))
        end.min_by { |flag_path| [File.mtime(flag_path), File.basename(flag_path)] }
      end

      def read_flag(path)
        flag = JSON.parse(File.read(path))
        ok, errors = Contracts.validate(:flag, flag)
        raise "invalid flag #{File.basename(path)}: #{errors.join(', ')}" unless ok

        flag
      end

      def judge(flag, enrichment)
        if @offline
          return local_judge(flag, enrichment, route: "offline-local", model: "rules")
        end

        model_judge(flag, enrichment)
      rescue StandardError => e
        local_judge(flag, enrichment, route: "frontier-fallback-local", model: "rules", error: e.message)
      end

      def model_judge(flag, enrichment)
        require "ruby_llm"

        api_key = ENV["ANTHROPIC_API_KEY"].to_s
        raise "ANTHROPIC_API_KEY is not set" if api_key.empty?

        RubyLLM.configure do |config|
          config.anthropic_api_key = api_key if config.respond_to?(:anthropic_api_key=)
        end

        model = ENV.fetch("INVESTIGATOR_MODEL", "claude-sonnet-4-20250514")
        prompt = build_prompt(flag, enrichment)
        chat = RubyLLM.chat(model: model)
        chat = chat.with_instructions(prompt[:system]) if chat.respond_to?(:with_instructions)
        response = chat.ask(prompt[:user])
        content = response.respond_to?(:content) ? response.content.to_s : response.to_s
        parsed = parse_model_json(content)
        validate_model_result(parsed)
        parsed.merge(
          "route" => "frontier",
          "model" => model,
          "tokens" => estimate_tokens(prompt[:system], prompt[:user], content),
          "cost_usd" => nil
        )
      end

      def build_prompt(flag, enrichment)
        skill_text = @use_skill ? load_skill_text : ""
        system = [SYSTEM_PROMPT, skill_text].reject(&:empty?).join("\n\n")
        user = JSON.pretty_generate(
          "flag" => flag,
          "enrichment" => enrichment,
          "instruction" => "Judge this single flag and return only the required JSON."
        )
        { system: system, user: user }
      end

      def load_skill_text
        parts = []
        parts << File.read(SKILL_PATH) if File.exist?(SKILL_PATH)
        Dir[SKILL_REFERENCES].sort.each { |path| parts << File.read(path) }
        parts.join("\n\n")
      end

      def parse_model_json(content)
        text = content.strip
        text = text[/\{.*\}/m] || text
        JSON.parse(text)
      end

      def validate_model_result(result)
        assessment = result["assessment"]
        confidence = result["confidence"]
        summary = result["summary"]
        unless %w[benign concern emergency].include?(assessment) &&
               confidence.is_a?(Numeric) &&
               confidence >= 0.0 &&
               confidence <= 1.0 &&
               summary.is_a?(String) &&
               !summary.strip.empty?
          raise "model returned invalid verdict JSON"
        end
      end

      def local_judge(flag, enrichment, route:, model:, error: nil)
        result = @use_skill ? skilled_local_judge(flag, enrichment) : baseline_local_judge(flag, enrichment)
        result.merge(
          "route" => route,
          "model" => model,
          "tokens" => 0,
          "cost_usd" => 0.0,
          "error" => error
        )
      end

      def skilled_local_judge(flag, enrichment)
        rule = flag["rule"]
        evidence = flag["evidence"] || {}
        squawk = evidence["squawk"].to_s
        context = enrichment["surface_context"].to_s
        metar = enrichment["metar"].to_s
        approach = kbos_approach?(flag, enrichment)
        fog = fog_or_low_visibility?(metar)
        open_water = context.include?("open water")
        gap_s = evidence["gap_s"].to_i

        if squawk == "7700"
          return verdict_result("emergency", 0.94, "7700 with no benign explanation in the flag context; treat as a live general emergency.")
        end

        if squawk == "7600" && fog && approach
          return verdict_result("benign", 0.86, "7600 on a foggy KBOS approach is consistent with routine lost-comms procedures.")
        end

        case rule
        when "rapid_descent"
          if approach
            verdict_result("benign", 0.82, "Rapid descent is within normal KBOS arrival context, not emergency behavior by itself.")
          else
            verdict_result("concern", 0.66, "Rapid descent away from a clear KBOS approach deserves follow-up.")
          end
        when "going_dark"
          if approach
            verdict_result("benign", 0.78, "Contact gap low near KBOS fits approach-area ADS-B coverage artifacts.")
          elsif open_water || gap_s >= 300
            verdict_result("concern", 0.76, "Aircraft is going dark away from a benign low-approach context, over/near open water.")
          else
            verdict_result("concern", 0.62, "Contact gap lacks enough benign context to dismiss.")
          end
        when "holding_pattern"
          if enrichment["nearest_airport"] == "KBOS"
            verdict_result("concern", 0.58, "Holding near KBOS is often flow control, but should be watched for weather or fuel context.")
          else
            verdict_result("concern", 0.65, "Holding pattern away from KBOS needs investigation.")
          end
        else
          verdict_result("concern", 0.55, "Flag has no clear benign explanation after enrichment.")
        end
      end

      def baseline_local_judge(flag, _enrichment)
        evidence = flag["evidence"] || {}
        squawk = evidence["squawk"].to_s

        return verdict_result("emergency", 0.92, "Emergency squawk detected; treat as a live emergency.") if squawk == "7700"
        return verdict_result("concern", 0.72, "Lost-comms squawk detected; investigate further.") if squawk == "7600"

        case flag["rule"]
        when "rapid_descent"
          verdict_result("concern", 0.72, "Rapid descent detected; investigate for abnormal flight path.")
        when "going_dark"
          verdict_result("concern", 0.75, "Aircraft contact is stale; investigate possible loss of surveillance.")
        else
          verdict_result("concern", 0.62, "Anomaly detected; investigate further.")
        end
      end

      def verdict_result(assessment, confidence, summary)
        { "assessment" => assessment, "confidence" => confidence, "summary" => summary }
      end

      def kbos_approach?(flag, enrichment)
        return true if enrichment["surface_context"].to_s.include?("KBOS terminal approach")
        return true if enrichment["surface_context"].to_s.include?("KBOS arrival corridor")

        distance = enrichment["nearest_airport_nm"]
        altitude = (flag.dig("evidence", "baro_alt_ft") || flag.dig("evidence", "altitude_ft")).to_f
        enrichment["nearest_airport"] == "KBOS" &&
          distance &&
          distance <= 18.0 &&
          (altitude.zero? || altitude <= 7000)
      end

      def fog_or_low_visibility?(metar)
        metar.include?(" FG") ||
          metar.include?(" BR") ||
          metar.match?(/\b[13]?\/?[24]SM\b/) ||
          metar.match?(/\bOVC00\d\b/) ||
          metar.match?(/\bBKN00\d\b/) ||
          metar.include?(" R")
      end

      def build_verdict(flag, enrichment, result)
        verdict = {
          "icao24" => flag["icao24"],
          "flag_ts" => flag["ts"],
          "assessment" => result["assessment"],
          "confidence" => result["confidence"],
          "summary" => result["summary"].to_s.strip,
          "enrichment" => enrichment
        }
        ok, errors = Contracts.validate(:verdict, verdict)
        raise "invalid verdict: #{errors.join(', ')}" unless ok

        verdict
      end

      def write_verdict(flag, verdict)
        path = File.join(@workspace, "verdicts", "#{flag['icao24']}-#{flag['ts']}.json")
        atomic_write_json(path, verdict)
      end

      def write_failure_verdict(flag_path, error)
        return unless flag_path && File.exist?(flag_path)

        flag = JSON.parse(File.read(flag_path))
        enrichment = Enrichment.for_flag(flag, offline: true)
        result = verdict_result("concern", 0.0, "Could not assess flag: #{error.message}")
        write_verdict(flag, build_verdict(flag, enrichment, result))
      rescue StandardError => e
        warn "investigator failure verdict error: #{e.class}: #{e.message}"
      end

      def atomic_write_json(path, object)
        tmp = "#{path}.tmp-#{$$}"
        File.write(tmp, JSON.pretty_generate(object) + "\n")
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      def verdict_path_for_filename(filename)
        File.join(@workspace, "verdicts", filename)
      end

      def record_observation(flag, result, latency_ms)
        path = File.join(@workspace, "observe", "run.jsonl")
        row = {
          "ts" => Time.now.to_i,
          "agent" => "investigator",
          "icao24" => flag["icao24"],
          "flag_ts" => flag["ts"],
          "assessment" => result["assessment"],
          "model" => result["model"],
          "route" => result["route"],
          "tokens" => result["tokens"],
          "cost_usd" => result["cost_usd"],
          "latency_ms" => latency_ms
        }
        File.open(path, "a") { |f| f.puts(JSON.generate(row)) }
      end

      def print_routing_table(result, latency_ms)
        puts "agent          model                 route                    tokens  cost_usd  latency_ms"
        puts "investigator   #{pad(result['model'], 20)}  #{pad(result['route'], 23)}  #{pad(result['tokens'], 6)}  #{pad(result['cost_usd'] || 0, 8)}  #{latency_ms}"
        puts "TOTAL          -                     -                        #{result['tokens'] || 0}       #{result['cost_usd'] || 0}       #{latency_ms}"
      end

      def pad(value, width)
        value.to_s[0, width].ljust(width)
      end

      def estimate_tokens(*strings)
        strings.join(" ").length / 4
      end
    end

    module_function

    def parse_options(argv)
      options = {
        offline: false,
        use_skill: true,
        once: false,
        workspace: File.join(ROOT, "workspace"),
        poll_interval: 1.0
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby agents/investigator.rb [options]"
        parser.on("--offline", "Use cached enrichment and local judgment; no network") { options[:offline] = true }
        parser.on("--no-skill", "Run without loading skills/flight-investigation") { options[:use_skill] = false }
        parser.on("--once", "Process one pending flag and exit") { options[:once] = true }
        parser.on("--workspace PATH", "Workspace file bus path") { |path| options[:workspace] = path }
        parser.on("--poll SECONDS", Float, "Polling interval for loop mode") { |seconds| options[:poll_interval] = seconds }
      end.parse!(argv)
      options
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = FlightWatch::Investigator.parse_options(ARGV)
  FlightWatch::Investigator::Runner.new(options).run
end
