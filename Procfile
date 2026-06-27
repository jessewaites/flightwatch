# Steady-state pipeline for foreman/overmind (demo mode, offline).
# Prefer `bin/demo` — it also resets the bus, sets demo mode, and detects ollama.
# Run `foreman start` from the repo root; reset the workspace first if needed.
producer:     ruby bin/produce_frames.rb --loop --interval 1.5
watcher:      ruby agents/watcher.rb --tracks workspace/tracks --poll 0.4 --no-skill
investigator: ruby agents/investigator.rb --offline --poll 0.4
synthesizer:  ruby agents/synthesizer.rb --offline
