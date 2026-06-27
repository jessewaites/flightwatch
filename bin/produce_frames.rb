#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Frame producer — the bridge from the data layer to the file bus, and the thing the UI toggle drives.
#
# It writes NORMALIZED frames as zero-padded JSON files into workspace/tracks/, where the Watcher polls.
# It reads workspace/control/mode.json (which the UI's realtime/demo toggle writes):
#   - demo     -> plays the planted replay capture from the start (the scripted scenario)
#   - realtime -> polls live OpenSky (empty if offline / no creds)
#
# Two run modes:
#   ruby bin/produce_frames.rb --daemon         # toggle-aware: runs forever, REPLAYS on each switch to demo
#   ruby bin/produce_frames.rb                   # play the demo replay once and exit (used by the smoke test)
#   ruby bin/produce_frames.rb --interval 0      # drain fast (smoke test)
#
# Frame filenames are a single monotonic sequence that NEVER resets, so the Watcher always sees each
# (re)played frame as new and re-detects it — that's what makes a fresh toggle-to-demo actually fire.

require "json"
require "fileutils"
require "optparse"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "data/lib/flightwatch/data")

# Lazily construct the realtime poller, and tolerate missing creds / no network so demo never dies on it.
class LazyRealtime
  def initialize(&factory)
    @factory = factory
    @source = nil
    @warned = false
  end

  def next_frame
    @source ||= @factory.call
    @source.next_frame
  rescue StandardError => e
    unless @warned
      warn "produce_frames: realtime poll failed (#{e.class}: #{e.message}); will keep retrying."
      @warned = true
    end
    nil
  end
end

options = {
  workspace: File.join(ROOT, "workspace"),
  replay: File.join(ROOT, "data/flightwatch-boston-planted-2026-06-22.jsonl"),
  interval: 1.5,
  realtime_interval: 6.0,
  limit: nil,
  loop: false,
  reset: false,
  daemon: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby bin/produce_frames.rb [options]"
  parser.on("--workspace PATH", "Workspace file-bus root") { |v| options[:workspace] = v }
  parser.on("--replay PATH", "Replay JSONL (demo mode source)") { |v| options[:replay] = v }
  parser.on("--interval SECONDS", Float, "Seconds between frames (0 = as fast as possible)") { |v| options[:interval] = v }
  parser.on("--realtime-interval SECONDS", Float, "Seconds between live OpenSky polls in realtime mode") { |v| options[:realtime_interval] = v }
  parser.on("--limit N", Integer, "Stop after N frames (play-once mode)") { |v| options[:limit] = v }
  parser.on("--loop", "Replay forever (play-once mode kiosk)") { options[:loop] = true }
  parser.on("--reset", "Clear workspace/tracks/*.json before starting") { options[:reset] = true }
  parser.on("--daemon", "Toggle-aware: run forever, follow control/mode.json, replay on each switch to demo") { options[:daemon] = true }
end.parse!

workspace = File.expand_path(options[:workspace])
tracks_dir = File.join(workspace, "tracks")
control_dir = File.join(workspace, "control")
mode_path = File.join(control_dir, "mode.json")
FileUtils.mkdir_p(tracks_dir)
FileUtils.mkdir_p(control_dir)

Dir[File.join(tracks_dir, "*.json")].each { |f| File.delete(f) } if options[:reset]

@seq = 0
def write_frame(tracks_dir, frame)
  @seq += 1
  path = File.join(tracks_dir, format("%06d.json", @seq))
  tmp = "#{path}.tmp-#{$$}"
  File.write(tmp, "#{JSON.generate(frame)}\n")
  File.rename(tmp, path)
  [@seq, frame]
end

def read_mode(mode_path)
  return "demo" unless File.file?(mode_path)

  JSON.parse(File.read(mode_path)).fetch("source", "demo")
rescue JSON::ParserError, Errno::ENOENT
  "demo"
end

# Wipe the runtime bus so a mode switch starts a clean run (no stale flags/verdicts/situations
# from the previous source). @seq stays monotonic, so the watcher still sees new frame files.
def reset_bus(workspace)
  %w[flags verdicts situations tracks].each do |dir|
    Dir[File.join(workspace, dir, "*.json")].each { |f| File.delete(f) rescue nil }
  end
end

demo = FlightWatch::Data::ReplayHarness.new(path: options[:replay], loop: options[:loop])
realtime = LazyRealtime.new do
  creds = FlightWatch::Data::Credentials.load
  token_manager = creds.complete? ? FlightWatch::Data::TokenManager.new(credentials: creds) : nil
  warn "produce_frames: no OpenSky credentials found; using anonymous access (rate-limited)." unless creds.complete?
  FlightWatch::Data::OpenSkyPoller.new(token_manager: token_manager)
end

puts "produce_frames: workspace=#{workspace} replay=#{File.basename(options[:replay])} " \
     "interval=#{options[:interval]}s mode=#{options[:daemon] ? 'daemon (toggle-aware)' : 'play-once'}"

if options[:daemon]
  # Toggle-aware daemon: follows control/mode.json and replays the planted scenario from the
  # start each time the user switches to demo. This is the process the UI toggle actually drives.
  # Checks control/mode.json FREQUENTLY (responsive to the UI toggle) but only EMITS a frame on each
  # mode's cadence. Triggers on every WRITE to mode.json (mtime change), so clicking "Demo" always
  # (re)starts the planted scenario from the first frame, near-instantly — even if demo was already active.
  prev_mtime = nil
  mode = read_mode(mode_path)
  demo_done = false
  last_emit = nil

  loop do
    mtime = File.file?(mode_path) ? File.mtime(mode_path) : nil
    if mtime != prev_mtime
      mode = read_mode(mode_path)
      reset_bus(workspace) # clean slate: clear the previous run's flags/verdicts/situations/tracks
      if mode == "demo"
        demo.rewind
        demo_done = false
        puts "-> DEMO: replaying planted scenario from the start (#{demo.count} frames)"
      else
        puts "-> REALTIME: polling live OpenSky (anonymous if no creds; map empty only if offline)"
      end
      prev_mtime = mtime
      last_emit = nil # emit the first frame of the new mode immediately
    end

    cadence = mode == "demo" ? options[:interval] : options[:realtime_interval]
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    if last_emit.nil? || (now - last_emit) >= cadence
      frame = mode == "demo" ? (demo_done ? nil : demo.next_frame) : realtime.next_frame

      if frame
        seq, _ = write_frame(tracks_dir, frame)
        aircraft = frame["aircraft"].is_a?(Array) ? frame["aircraft"].length : 0
        puts "   frame #{format('%06d', seq)} ts=#{frame['ts']} aircraft=#{aircraft} (#{mode})"
        last_emit = now
      elsif mode == "demo" && !demo_done
        demo_done = true
        puts "   demo scenario finished; holding. Click Demo to replay."
        last_emit = now
      else
        last_emit = now # realtime hiccup or demo holding — respect cadence, keep checking the toggle
      end
    end

    sleep 0.2
  end
else
  # Play-once: play the demo replay through and exit (used by bin/pipeline_smoke.sh).
  File.write(mode_path, %({"source":"demo"}\n)) unless File.exist?(mode_path)
  source = FlightWatch::Data::FrameSource.new(realtime_source: realtime, demo_source: demo, mode_path: mode_path)
  emitted = 0

  loop do
    frame = source.next_frame
    if frame
      seq, _ = write_frame(tracks_dir, frame)
      emitted += 1
      aircraft = frame["aircraft"].is_a?(Array) ? frame["aircraft"].length : 0
      puts "   frame #{format('%06d', seq)} ts=#{frame['ts']} aircraft=#{aircraft} (mode=#{source.mode})"
    elsif source.mode == "demo" && !options[:loop]
      puts "produce_frames: demo replay exhausted after #{emitted} frames; exiting."
      break
    end

    break if options[:limit] && emitted >= options[:limit]

    sleep options[:interval] if options[:interval].positive?
  end
end
