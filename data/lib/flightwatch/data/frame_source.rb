# frozen_string_literal: true

require "json"

module FlightWatch
  module Data
    class FrameSource
      DEFAULT_MODE_PATH = File.expand_path("../../../../workspace/control/mode.json", __dir__)

      def initialize(realtime_source:, demo_source:, mode_path: DEFAULT_MODE_PATH)
        @realtime_source = realtime_source
        @demo_source = demo_source
        @mode_path = mode_path
      end

      def next_frame
        source.next_frame
      end

      def each_frame(interval_seconds: 5, limit: nil)
        return enum_for(:each_frame, interval_seconds: interval_seconds, limit: limit) unless block_given?

        emitted = 0
        loop do
          break if limit && emitted >= limit

          frame = next_frame
          yield frame if frame
          emitted += 1
          sleep interval_seconds if interval_seconds.positive? && (!limit || emitted < limit)
        end
      end

      def mode
        return "demo" unless File.file?(@mode_path)

        parsed = JSON.parse(File.read(@mode_path))
        parsed.fetch("source", "demo")
      rescue JSON::ParserError
        "demo"
      end

      private

      def source
        case mode
        when "realtime"
          @realtime_source
        when "demo"
          @demo_source
        else
          @demo_source
        end
      end
    end
  end
end
