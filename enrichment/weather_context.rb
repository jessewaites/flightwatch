# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "securerandom"
require "timeout"

module FlightWatch
  class WeatherContext
    BOSTON_LOGAN = {
      "airport" => "KBOS",
      "lat" => 42.3656,
      "lon" => -71.0096,
      "timezone" => "America/New_York"
    }.freeze

    MCP_COMMAND = ["npx", "-y", "-p", "open-meteo-mcp-server", "open-meteo-mcp-server"].freeze
    CURRENT_FIELDS = %w[
      temperature_2m
      weather_code
      visibility
      wind_speed_10m
      wind_direction_10m
      wind_gusts_10m
      cloud_cover
      precipitation
    ].freeze

    attr_reader :workspace_dir, :offline, :timeout_s

    def initialize(workspace_dir: File.expand_path("../workspace", __dir__), offline: false, timeout_s: 30)
      @workspace_dir = workspace_dir
      @offline = offline
      @timeout_s = timeout_s
    end

    def refresh
      snapshot = offline ? self.class.fixture_snapshot(fetched_at: Time.now.to_i) : fetch_open_meteo_snapshot
      write_snapshot(snapshot)
      snapshot
    rescue StandardError => e
      observe("weather_context_fallback", error: "#{e.class}: #{e.message}")
      snapshot = self.class.fixture_snapshot(fetched_at: Time.now.to_i, source: "open-meteo-mcp-fallback")
      write_snapshot(snapshot)
      snapshot
    end

    def fetch_open_meteo_snapshot
      forecast = McpClient.new(command: MCP_COMMAND, timeout_s: timeout_s).call_tool(
        "weather_forecast",
        {
          "latitude" => BOSTON_LOGAN.fetch("lat"),
          "longitude" => BOSTON_LOGAN.fetch("lon"),
          "current" => CURRENT_FIELDS,
          "temperature_unit" => "fahrenheit",
          "wind_speed_unit" => "kn",
          "precipitation_unit" => "inch",
          "timezone" => BOSTON_LOGAN.fetch("timezone"),
          "forecast_days" => 1
        }
      )
      self.class.snapshot_from_forecast(forecast, fetched_at: Time.now.to_i)
    end

    def write_snapshot(snapshot)
      FileUtils.mkdir_p(weather_dir)
      final_path = File.join(weather_dir, "kbos.json")
      tmp_path = "#{final_path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp_path, JSON.pretty_generate(snapshot) + "\n")
      File.rename(tmp_path, final_path)
      observe("weather_context_written", path: final_path, source: snapshot["source"])
    ensure
      FileUtils.rm_f(tmp_path) if tmp_path && File.exist?(tmp_path)
    end

    def weather_dir
      File.join(workspace_dir, "weather")
    end

    def observe_dir
      File.join(workspace_dir, "observe")
    end

    def observe(event, attrs = {})
      FileUtils.mkdir_p(observe_dir)
      line = { ts: Time.now.to_i, agent: "weather_context", event: event }.merge(attrs)
      File.open(File.join(observe_dir, "run.jsonl"), "a") { |f| f.puts(JSON.generate(line)) }
    rescue StandardError
      nil
    end

    def self.snapshot_from_forecast(forecast, fetched_at:)
      current = forecast.fetch("current", {})
      units = forecast.fetch("current_units", {})

      {
        "airport" => BOSTON_LOGAN.fetch("airport"),
        "source" => "open-meteo-mcp",
        "fetched_at" => fetched_at,
        "location" => {
          "lat" => forecast["latitude"] || BOSTON_LOGAN.fetch("lat"),
          "lon" => forecast["longitude"] || BOSTON_LOGAN.fetch("lon")
        },
        "summary" => summary_for(current, units),
        "current" => current,
        "units" => units
      }
    end

    def self.fixture_snapshot(fetched_at:, source: "offline-fixture")
      current = {
        "time" => Time.at(fetched_at).utc.strftime("%Y-%m-%dT%H:%MZ"),
        "temperature_2m" => 68.0,
        "weather_code" => 1,
        "visibility" => 52_800.0,
        "wind_speed_10m" => 8.0,
        "wind_direction_10m" => 80,
        "wind_gusts_10m" => 12.0,
        "cloud_cover" => 25,
        "precipitation" => 0.0
      }
      units = {
        "temperature_2m" => "F",
        "weather_code" => "wmo code",
        "visibility" => "ft",
        "wind_speed_10m" => "kn",
        "wind_direction_10m" => "deg",
        "wind_gusts_10m" => "kn",
        "cloud_cover" => "%",
        "precipitation" => "inch"
      }

      {
        "airport" => BOSTON_LOGAN.fetch("airport"),
        "source" => source,
        "fetched_at" => fetched_at,
        "location" => { "lat" => BOSTON_LOGAN.fetch("lat"), "lon" => BOSTON_LOGAN.fetch("lon") },
        "summary" => summary_for(current, units),
        "current" => current,
        "units" => units
      }
    end

    def self.summary_for(current, _units)
      weather = weather_code_label(current["weather_code"])
      temp = format_number(current["temperature_2m"])
      wind_speed = format_number(current["wind_speed_10m"])
      wind_gust = format_number(current["wind_gusts_10m"])
      wind_dir = compass_direction(current["wind_direction_10m"])
      visibility = visibility_sm(current["visibility"])
      clouds = format_number(current["cloud_cover"])
      precip = current["precipitation"].to_f

      parts = ["Open-Meteo KBOS: #{weather}"]
      parts << "#{temp} F" if temp
      parts << "#{wind_dir} wind #{wind_speed} kt#{wind_gust ? " gust #{wind_gust} kt" : ""}" if wind_speed
      parts << "visibility #{visibility} sm" if visibility
      parts << "clouds #{clouds}%" if clouds
      parts << (precip.positive? ? "precipitation #{format_number(precip)} in" : "no precipitation")
      parts.join(", ") + "."
    end

    def self.weather_code_label(code)
      case code.to_i
      when 0 then "clear"
      when 1 then "mainly clear"
      when 2 then "partly cloudy"
      when 3 then "overcast"
      when 45, 48 then "fog"
      when 51, 53, 55, 56, 57 then "drizzle"
      when 61, 63, 65, 66, 67 then "rain"
      when 71, 73, 75, 77 then "snow"
      when 80, 81, 82 then "rain showers"
      when 95, 96, 99 then "thunderstorm"
      else "weather code #{code}"
      end
    end

    def self.compass_direction(degrees)
      return nil unless degrees

      directions = %w[N NE E SE S SW W NW]
      directions[((degrees.to_f + 22.5) / 45.0).floor % directions.length]
    end

    def self.visibility_sm(feet)
      return nil unless feet

      format_number(feet.to_f / 5280.0)
    end

    def self.format_number(value)
      return nil if value.nil?

      number = value.to_f
      rounded = number.round(number.abs >= 10 ? 0 : 1)
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
    end

    class McpClient
      attr_reader :command, :timeout_s

      def initialize(command:, timeout_s:)
        @command = command
        @timeout_s = timeout_s
      end

      def call_tool(name, arguments)
        Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
          drain_stderr(stderr)
          request_id = 0

          request_id += 1
          write_message(stdin, {
            "jsonrpc" => "2.0",
            "id" => request_id,
            "method" => "initialize",
            "params" => {
              "protocolVersion" => "2024-11-05",
              "capabilities" => {},
              "clientInfo" => { "name" => "flightwatch-weather-context", "version" => "0.1.0" }
            }
          })
          read_response(stdout, request_id)

          write_message(stdin, { "jsonrpc" => "2.0", "method" => "notifications/initialized", "params" => {} })

          request_id += 1
          write_message(stdin, {
            "jsonrpc" => "2.0",
            "id" => request_id,
            "method" => "tools/call",
            "params" => { "name" => name, "arguments" => arguments }
          })
          response = read_response(stdout, request_id)
          raise "mcp error: #{response["error"].inspect}" if response["error"]

          parse_tool_content(response)
        ensure
          begin
            stdin.close
          rescue StandardError
            nil
          end
          if wait_thr && wait_thr.alive?
            begin
              Process.kill("TERM", wait_thr.pid)
            rescue StandardError
              nil
            end
          end
        end
      end

      private

      def drain_stderr(stderr)
        Thread.new do
          begin
            stderr.each_line { |_line| }
          rescue IOError
            nil
          end
        end
      end

      def write_message(stdin, message)
        stdin.puts(JSON.generate(message))
        stdin.flush
      end

      def read_response(stdout, id)
        Timeout.timeout(timeout_s) do
          loop do
            line = stdout.gets
            raise "mcp server closed stdout" unless line

            message = JSON.parse(line)
            return message if message["id"] == id
          rescue JSON::ParserError
            next
          end
        end
      end

      def parse_tool_content(response)
        text = response.dig("result", "content", 0, "text")
        raise "mcp response missing text content" if text.to_s.strip.empty?

        JSON.parse(text)
      end
    end
  end
end
