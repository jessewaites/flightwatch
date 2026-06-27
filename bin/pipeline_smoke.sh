#!/usr/bin/env bash
#
# End-to-end pipeline smoke test (offline, deterministic).
# Runs the whole spine ONCE over the planted capture and asserts the chain:
#   weather + producer -> watcher -> investigator -> synthesizer
#   context + frames   -> flags    -> verdicts     -> situations
#
# This is the Phase 2 integration test and the demo insurance: if this passes, the demo works.
# No network, no ollama, no API key required — investigator/synthesizer run --offline.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Optional workspace path (default: the live workspace). Pass a throwaway dir to avoid touching it.
WS="${1:-$ROOT/workspace}"
mkdir -p "$WS"

count() { ls "$WS/$1"/*.json 2>/dev/null | wc -l | tr -d ' '; }

echo "== reset workspace =="
for d in flags verdicts situations tracks observe weather; do
  mkdir -p "$WS/$d"
  find "$WS/$d" -name '*.json' -delete 2>/dev/null
done
mkdir -p "$WS/control"
echo '{"source":"demo"}' > "$WS/control/mode.json"

echo "== 1. producer: planted replay -> workspace/tracks/ =="
ruby bin/produce_frames.rb --workspace "$WS" --reset --interval 0 >/dev/null
echo "   frames: $(count tracks)"

echo "== 2. watcher: frames -> flags (--no-skill, deterministic) =="
ruby agents/watcher.rb --workspace "$WS" --tracks "$WS/tracks" --once --no-skill >/dev/null
echo "   flags: $(count flags)"

echo "== 3. investigator: flags -> verdicts (--offline) =="
i=0
while [ "$(count flags)" -gt "$(count verdicts)" ] && [ "$i" -lt 200 ]; do
  ruby agents/investigator.rb --workspace "$WS" --once --offline >/dev/null
  i=$((i+1))
done
echo "   verdicts: $(count verdicts)"

echo "== 4. weather context: Open-Meteo fixture -> workspace/weather/ =="
ruby bin/weather_context.rb --workspace "$WS" --once --offline >/dev/null
echo "   weather: $(count weather)"

echo "== 5. synthesizer: flags+verdicts+weather -> situations (--offline) =="
ruby agents/synthesizer.rb --workspace "$WS" --once --offline >/dev/null
echo "   situations: $(count situations)"

echo "== assertions =="
fail=0
flags=$(count flags); verdicts=$(count verdicts); situations=$(count situations)
[ "$flags"      -gt 0 ]          && echo "  PASS flags > 0 ($flags)"                 || { echo "  FAIL flags == 0"; fail=1; }
[ "$verdicts" -eq "$flags" ]     && echo "  PASS verdicts == flags ($verdicts)"      || { echo "  FAIL verdicts ($verdicts) != flags ($flags)"; fail=1; }
[ "$situations" -ge 1 ]          && echo "  PASS situations >= 1 ($situations)"      || { echo "  FAIL situations == 0"; fail=1; }

echo
if [ "$fail" -eq 0 ]; then
  echo "PIPELINE SMOKE: PASS — flags=$flags verdicts=$verdicts situations=$situations"
  echo "--- flags by rule ---"
  cat "$WS"/flags/*.json | ruby -rjson -e 'h=Hash.new(0); STDIN.read.scan(/"rule":\s*"([^"]+)"/){|m| h[m[0]]+=1}; h.sort.each{|k,v| puts "  #{k}: #{v}"}'
  echo "--- situations ---"
  for s in "$WS"/situations/*.json; do ruby -rjson -e "s=JSON.parse(File.read(ARGV[0])); puts \"  #{s['kind']} @ #{s['airport']} (#{s['icao24s'].length} aircraft): #{s['summary']}\"" "$s"; done
  exit 0
else
  echo "PIPELINE SMOKE: FAIL"
  exit 1
fi
