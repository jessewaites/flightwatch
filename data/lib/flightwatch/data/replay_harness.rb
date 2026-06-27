# frozen_string_literal: true

require "json"

module FlightWatch
  module Data
    class ReplayHarness
      DEFAULT_PATH = File.expand_path("../../../flightwatch-boston-raw-2026-06-22.jsonl", __dir__)

      attr_reader :path

      def initialize(path: DEFAULT_PATH, loop: false)
        @path = path
        @loop = loop
        @lines = File.readlines(path, chomp: true).reject(&:empty?)
        raise "Replay capture is empty: #{path}" if @lines.empty?

        @index = 0
      end

      def next_raw
        return nil if finished? && !@loop

        @index = 0 if finished? && @loop
        raw = JSON.parse(@lines.fetch(@index))
        @index += 1
        raw
      end

      def next_frame
        raw = next_raw
        raw && Normalizer.normalize(raw)
      end

      def each_frame
        return enum_for(:each_frame) unless block_given?

        while (frame = next_frame)
          yield frame
        end
      end

      def rewind
        @index = 0
      end

      def count
        @lines.length
      end

      private

      def finished?
        @index >= @lines.length
      end
    end
  end
end
