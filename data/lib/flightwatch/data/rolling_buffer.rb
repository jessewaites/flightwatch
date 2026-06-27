# frozen_string_literal: true

module FlightWatch
  module Data
    class RollingBuffer
      DEFAULT_MAX_FRAMES = 60
      DEFAULT_EVICT_AFTER_SECONDS = 300

      def initialize(max_frames: DEFAULT_MAX_FRAMES, evict_after_seconds: DEFAULT_EVICT_AFTER_SECONDS)
        @max_frames = max_frames
        @evict_after_seconds = evict_after_seconds
        @tracks = {}
      end

      def ingest(frame)
        frame_ts = Integer(frame.fetch("ts"))

        frame.fetch("aircraft").each do |aircraft|
          icao24 = aircraft.fetch("icao24")
          @tracks[icao24] ||= []
          @tracks[icao24] << aircraft.merge("ts" => frame_ts)
          @tracks[icao24] = @tracks[icao24].last(@max_frames)
        end

        evict_stale!(frame_ts)
        frame
      end

      def recent_track(icao24)
        Array(@tracks[icao24]).map(&:dup)
      end

      def include?(icao24)
        @tracks.key?(icao24)
      end

      def size
        @tracks.size
      end

      private

      def evict_stale!(frame_ts)
        @tracks.delete_if do |_icao24, track|
          last = track.last
          last_contact = Integer(last.fetch("last_contact"))
          frame_ts - last_contact > @evict_after_seconds
        end
      end
    end
  end
end
