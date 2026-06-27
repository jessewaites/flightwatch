# FlightWatch

Multi-agent airspace anomaly detection over Boston. Lane 3 — The Open Accelerator Agent Build Day.

Watcher (local granite4:micro) flags planes by rule -> Investigator (frontier) judges each flag ->
Synthesizer names emergent situations. Agents communicate through the `workspace/` file bus.

Data source: OpenSky Network (https://opensky-network.org). Used non-commercially.

## Running it

**Offline demo (no network/keys needed):**
```bash
# terminal 1 (optional, for the watcher's model triage): ollama serve   # needs granite4:micro
# terminal 2 (the dashboard):
cd ui && bundle install && bin/dev          # http://localhost:3000  (reads ../workspace)
# terminal 3 (the pipeline):
bin/demo                                     # resets the bus, plays the planted replay
```
`bin/demo` boots the frame producer + all three agents against `workspace/`, in `--offline` mode
(investigator/synthesizer use local rules; watcher falls back to deterministic triage if ollama is
down). Use `bin/demo --with-ui` to also boot Rails. `INTERVAL=1.0 bin/demo` for a faster replay.

**End-to-end smoke test (demo insurance):**
```bash
bin/pipeline_smoke.sh     # runs the spine once over the planted capture, asserts the full chain
```

**Pieces, individually:**
```bash
ruby bin/produce_frames.rb --reset            # data layer -> workspace/tracks/ (the frame bus)
ruby agents/watcher.rb --tracks workspace/tracks --poll 0.4   # frames -> flags (--no-skill to skip ollama)
ruby agents/investigator.rb --offline --poll 0.4             # flags  -> verdicts
ruby agents/synthesizer.rb --offline                         # flags+verdicts -> situations
ruby contracts/validate.rb                                   # check fixtures against frozen schemas
```
Online mode: drop `--offline`, set `ANTHROPIC_API_KEY`, and put OpenSky creds in `.env`/`credentials.json`.

## Layout
- `contracts/` frozen schemas + fixtures (Phase 0; do not edit after freeze)
- `data/` capture, replay, rolling buffer, raw capture
- `agents/` watcher.rb, investigator.rb, synthesizer.rb (Ruby + RubyLLM)
- `skills/` agentskills.io skills (validate with `agentskills validate ./skills/<name>`)
- `enrichment/` METAR + airport lookups
- `evals/` planted-anomaly eval (with-skill vs --no-skill)
- `ui/` stripped Rails + Action Cable + Leaflet + Tailwind (created via `rails new`)
- `workspace/` runtime delegation bus (flags/ verdicts/ situations/ tracks/)

License: MIT
