# Agent pipeline for foreman/overmind. Source (demo/realtime) is controlled by the UI toggle, not here.
# Prefer `bin/pipeline` — it also resets the bus and detects ollama.
producer:     ruby bin/produce_frames.rb --daemon --interval 1.5
watcher:      ruby agents/watcher.rb --tracks workspace/tracks --poll 0.4 --no-skill
investigator: ruby agents/investigator.rb --offline --poll 0.4
synthesizer:  ruby agents/synthesizer.rb --offline
