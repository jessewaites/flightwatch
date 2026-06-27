#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Frame producer — the bridge from the data layer to the file bus.
#
# Reads NORMALIZED frames (replay in demo mode, live OpenSky in realtime mode, toggled by
# workspace/control/mode.json) and writes each frame as a zero-padded JSON file into
# workspace/tracks/, which is exactly where the Watcher polls for frames. This is the piece
# that was missing between Track A (data lib, yields frames in-process) and Track B (watcher,
# consumes frame files).
#
# Usage:
#   ruby bin/produce_frames.rb                       # play planted replay into the bus, ~1.5s/frame, then exit
#   ruby bin/produce_frames.rb --interval 0 --reset  # drain the whole replay fast (used by the smoke test)
#   ruby bin/produce_frames.rb --loop                # kiosk: replay forever
#   ruby bin/produce_frames.rb --replay data/flightwatch-boston-raw-2026-06-22.jsonl

require "json"
require "fileutils"
require "optparse"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "data/lib/flightwatch/data")

# Lazily construct the realtime poller only if/when demo is toggled to realtime, and tolerate
# missing credentials / no network so an offline demo never dies on the realtime source.
class LazyRealtime
  def initialize(&factory)
    @factory = factory
    @source = nil
    @failed = false
  end

  def next_frame
    return nil if @failed

    @source ||= @factory.call
    @source.next_frame
  rescue StandardError => e
    @failed = true
    warn "produce_frames: realtime source unavailable (#{e.class}: #{e.message}); holding."
    nil
  end
end

options = {
  workspace: File.join(ROOT, "workspace"),
  replay: File.join(ROOT, "data/flightwatch-boston-planted-2026-06-22.jsonl"),
  interval: 1.5,
  limit: nil,
  loop: false,
  reset: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby bin/produce_frames.rb [options]"
  parser.on("--workspace PATH", "Workspace file-bus root") { |v| options[:workspace] = v }
  parser.on("--replay PATH", "Replay JSONL (demo mode source)") { |v| options[:replay] = v }
  parser.on("--interval SECONDS", Float, "Seconds between frames (0 = as fast as possible)") { |v| options[:interval] = v }
  parser.on("--limit N", Integer, "Stop after N frames") { |v| options[:limit] = v }
  parser.on("--loop", "Replay forever (kiosk)") { options[:loop] = true }
  parser.on("--reset", "Clear workspace/tracks/*.json before starting") { options[:reset] = true }
end.parse!

workspace = File.expand_path(options[:workspace])
tracks_dir = File.join(workspace, "tracks")
control_dir = File.join(workspace, "control")
mode_path = File.join(control_dir, "mode.json")
FileUtils.mkdir_p(tracks_dir)
FileUtils.mkdir_p(control_dir)

if options[:reset]
  Dir[File.join(tracks_dir, "*.json")].each { |f| File.delete(f) }
end

# Default the toggle to demo so a bare run is self-contained.
File.write(mode_path, %({"source":"demo"}\n)) unless File.exist?(mode_path)

demo = FlightWatch::Data::ReplayHarness.new(path: options[:replay], loop: options[:loop])
realtime = LazyRealtime.new do
  FlightWatch::Data::OpenSkyPoller.new(
    token_manager: FlightWatch::Data::TokenManager.new(credentials: FlightWatch::Data::Credentials.load)
  )
end
source = FlightWatch::Data::FrameSource.new(realtime_source: realtime, demo_source: demo, mode_path: mode_path)

def write_frame(tracks_dir, seq, frame)
  path = File.join(tracks_dir, format("%05d.json", seq))
  tmp = "#{path}.tmp-#{$$}"
  File.write(tmp, "#{JSON.generate(frame)}\n")
  File.rename(tmp, path)
end

seq = 0
emitted = 0
puts "produce_frames: workspace=#{workspace} replay=#{File.basename(options[:replay])} interval=#{options[:interval]}s"

loop do
  frame = source.next_frame

  if frame
    seq += 1
    emitted += 1
    write_frame(tracks_dir, seq, frame)
    aircraft = frame["aircraft"].is_a?(Array) ? frame["aircraft"].length : 0
    puts "  frame #{format('%05d', seq)} ts=#{frame['ts']} aircraft=#{aircraft} (mode=#{source.mode})"
  else
    # No frame: in demo mode without --loop this means the replay is exhausted → done.
    if source.mode == "demo" && !options[:loop]
      puts "produce_frames: demo replay exhausted after #{emitted} frames; exiting."
      break
    end
    # Realtime hiccup or between-poll gap: wait and retry rather than dying.
  end

  break if options[:limit] && emitted >= options[:limit]

  sleep options[:interval] if options[:interval].positive?
end
