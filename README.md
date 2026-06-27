# FlightWatch

Multi-agent airspace anomaly detection over Boston. Lane 3 — The Open Accelerator Agent Build Day.

Watcher (local granite4:micro) flags planes by rule -> Investigator (frontier) judges each flag ->
Synthesizer names emergent situations. Agents communicate through the `workspace/` file bus.

Data source: OpenSky Network (https://opensky-network.org). Used non-commercially.

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
