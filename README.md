# FlightWatch

Multi-agent airspace anomaly detection over Boston. Lane 3 — The Open Accelerator Agent Build Day.

Watcher (local granite4:micro) flags planes by rule -> Investigator (frontier) judges each flag ->
Synthesizer names emergent situations with light Boston weather context from Open-Meteo MCP.
Agents communicate through the `workspace/` file bus.

Data source: OpenSky Network (https://opensky-network.org). Used non-commercially.

## Running it

> **Judges / first run — fully offline, no API keys, no network.** Demo mode runs off a planted
> capture, so it needs **no OpenSky credentials and no `ANTHROPIC_API_KEY`**. Requires **Ruby ≥ 3.2**.
>
> ```bash
> bundle install                  # repo root — agent + eval gems
> cd ui && bundle install         # Rails UI gems
> bin/rails tailwindcss:build     # build the CSS once (see "CSS note" below), then: cd ..
> ```
> Prove it runs without booting a server:
> ```bash
> bin/pipeline_smoke.sh           # full agent chain over the planted capture → PASS
> ruby evals/run_all.rb           # scored skill delta (with-skill vs --no-skill) → PASS, +0.6 accuracy
> ```
> Then the live dashboard:
> ```bash
> cd ui && bin/dev                # http://localhost:3000  (also builds CSS via tailwindcss:watch)
> bin/pipeline                    # another terminal, from repo root; click "Demo" in the UI
> ```
> **CSS note:** `ui/app/assets/builds/tailwind.css` is a gitignored build artifact. `bin/dev` builds it
> automatically (give it a few seconds on first boot). If you instead start the server with
> `bin/rails server` directly, run `bin/rails tailwindcss:build` first — otherwise pages return
> `500: asset 'tailwind.css' was not found`.

Two processes: the **Rails UI** and the **agent pipeline**. Demo-vs-realtime is chosen at runtime by
the UI toggle (`workspace/control/mode.json`) — nothing hardcodes a mode.
```bash
# terminal 1 (optional, for the watcher's model triage): ollama serve   # needs granite4:micro
# terminal 2 (the dashboard):
cd ui && bundle install && bin/dev          # http://localhost:3000  (reads ../workspace)
# terminal 3 (the agent pipeline):
bin/pipeline                                 # frame producer + watcher + investigator + synthesizer
```
`bin/pipeline` boots the backend processes against `workspace/` (investigator/synthesizer `--offline`;
watcher falls back to deterministic triage if ollama is down; weather writes `workspace/weather/kbos.json`
through `open-meteo-mcp-server`). The **frame producer follows the UI
toggle**: Real-time → live OpenSky (anonymous if no creds), Demo → plays the planted replay from the
start. `INTERVAL=1.0 bin/pipeline` for a faster replay.

**End-to-end smoke test (demo insurance):**
```bash
bin/pipeline_smoke.sh     # runs the spine once over the planted capture, asserts the full chain
```

**Eval gate:**
```bash
ruby evals/run_all.rb     # emits evals/evals.json and benchmark.json
```

**Pieces, individually:**
```bash
ruby bin/produce_frames.rb --reset            # data layer -> workspace/tracks/ (the frame bus)
ruby agents/watcher.rb --tracks workspace/tracks --poll 0.4   # frames -> flags (--no-skill to skip ollama)
ruby agents/investigator.rb --offline --poll 0.4             # flags  -> verdicts
ruby bin/weather_context.rb --once                           # Open-Meteo MCP -> workspace/weather/kbos.json
ruby agents/synthesizer.rb --offline                         # flags+verdicts -> situations
ruby contracts/validate.rb                                   # check fixtures against frozen schemas
```
Online mode: drop `--offline`, set `ANTHROPIC_API_KEY`, and put OpenSky creds in `.env`/`credentials.json`.
Weather context requires Node 22+ and uses `npx -y -p open-meteo-mcp-server open-meteo-mcp-server`;
use `ruby bin/weather_context.rb --once --offline` for the deterministic fixture.

## Layout
- `contracts/` frozen schemas + fixtures (Phase 0; do not edit after freeze)
- `data/` capture, replay, rolling buffer, raw capture
- `agents/` watcher.rb, investigator.rb, synthesizer.rb (Ruby + RubyLLM)
- `skills/` agentskills.io skills (validate with `agentskills validate ./skills/<name>`)
- `enrichment/` METAR + airport lookups
- `evals/` planted-anomaly eval (with-skill vs --no-skill)
- `ui/` stripped Rails + Action Cable + Leaflet + Tailwind (created via `rails new`)
- `workspace/` runtime delegation bus (flags/ verdicts/ situations/ tracks/ weather/)

## Judging artifacts

- ADLC worksheet: `docs/adlc-worksheet.md`
- Model-selection rationale: `docs/model-selection-rationale.md`
- Eval aggregate: `benchmark.json`
- Scored cases: `evals/evals.json`

License: MIT
