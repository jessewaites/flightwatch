#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

require_relative "../enrichment/weather_context"

options = {
  workspace_dir: File.expand_path("../workspace", __dir__),
  once: false,
  offline: false,
  interval_s: 300
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby bin/weather_context.rb [--workspace DIR] [--once] [--offline] [--interval SECONDS]"
  opts.on("--workspace DIR", "Workspace file bus root") { |dir| options[:workspace_dir] = dir }
  opts.on("--once", "Refresh weather once and exit") { options[:once] = true }
  opts.on("--offline", "Use a deterministic KBOS weather fixture") { options[:offline] = true }
  opts.on("--interval SECONDS", Integer, "Refresh interval for daemon mode") { |seconds| options[:interval_s] = seconds }
end.parse!

loop do
  FlightWatch::WeatherContext.new(
    workspace_dir: options[:workspace_dir],
    offline: options[:offline]
  ).refresh
  break if options[:once]

  sleep options[:interval_s]
end
