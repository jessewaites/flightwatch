# FlightWatch — working notes

**FlightWatch** is a 3-agent system over live Boston air traffic, built for The Open Accelerator Agent
Build Day (Lane 3). The parallel build is **done** — all six tracks (A–F) merged to `main`. We are now
**integrating and tuning** toward the demo. The full strategy doc is `flightwatch-build-spec-final.md`
(source of truth); per-track kickoff briefs are archived in `briefs/`.

## What it is, in one breath
**Watcher** (local granite4:micro) flags planes by deterministic rule → **Investigator** (frontier
Claude) judges each flag → **Synthesizer** (frontier) names situations across flags. Agents talk ONLY
through the `workspace/` file bus. A small weather producer writes Open-Meteo MCP context to that same bus.
A Rails + Leaflet UI renders it live. The demo runs off a
pre-recorded + planted capture (`--offline`), never the live sky.

## Where things live
| Path | What |
|------|------|
| `contracts/` | **FROZEN** schemas + `validate.rb` + fixtures. The shared seam — don't break it while tuning. |
| `agents/` | `watcher.rb`, `investigator.rb`, `synthesizer.rb` + their `*.md` identity docs. |
| `skills/` | the 3 validated skills (`agentskills validate ./skills/<name>`). |
| `data/` | OpenSky capture, replay, rolling buffer, raw + planted JSONL. |
| `enrichment/` | METAR + airport lookups (Investigator), Open-Meteo weather context (Synthesizer). |
| `evals/` | planting script + the two gates; emits `evals/evals.json` + root `benchmark.json`. |
| `ui/` | Rails + Action Cable + Leaflet + Tailwind dashboard. |
| `workspace/` | runtime file bus: `flags/ verdicts/ situations/ control/ tracks/ weather/ observe/` (contents gitignored). |

## Still the most important thing: the eval gate
A skill scores ONLY if it beats a no-skill baseline. **That delta is the whole game.** The scored
artifact is the **Investigator's `flight-investigation` skill** (with-skill vs `--no-skill` on fixture
verdict cases) — NOT the Watcher's detect-on/off (that just proves `detect.rb` ran). When tuning, protect
this number first.

## Decisions that are settled — do NOT relitigate
- **Ruby + RubyLLM.** Not Python/LangChain. (`detect.rb` may be Python behind the frozen signature.)
- **No database.** State = `workspace/` JSON + in-memory rolling buffer. No Postgres/ActiveRecord.
- **Delegation is the file bus** — not in-process calls, not MCP between agents, not sub-agents. The only
  MCP usage is the external Open-Meteo weather producer writing `workspace/weather/kbos.json`.
- **Detection is deterministic code; judgment is the model.** Never make the watcher "detect" with an LLM.
- **Simpler beats clever.** Don't add agents/frameworks/services. The system is complete; from here it's tuning.
- **Contracts are frozen.** If something genuinely needs a schema change, change `contracts/validate.rb`
  AND every reader/writer together, run `ruby contracts/validate.rb`, and say so — never drift silently.

## TRAPS that bit this project (still true while tuning)
- **Squawk is field index 14, NOT 15.** Index 15 is `spi` (boolean). The hero 7700 rule depends on 14.
- **OpenSky units are METRIC.** `vertical_rate` m/s, altitudes meters. Converted to ft / ft·min⁻¹ once at
  frame normalization (Track A). Don't re-convert downstream.
- **Filter on-ground aircraft.** Parked/taxiing at Logan (`on_ground=true`) must never flag.
- **"Going dark" is staleness, not a missing row.** Gap between frame `ts` and the plane's `last_contact`.
- **Validator is `agentskills`, NOT `skills-ref`.** `agentskills validate ./skills/<name>`.
- **OpenSky auth = OAuth2 client-credentials**, token expires every 30 min (auto-refresh). Stay on the
  laptop's IP. `credentials.json` + `.env` stay gitignored.

## Scoring artifacts — keep these working while tuning
- **Routing table:** per-agent table after every run (agent · model · route · tokens · $ · latency ·
  TOTAL). Watcher ≈ $0; investigator/synthesizer show real cost but fire rarely. Shown in print AND as a
  dashboard panel. Include the "frontier→local fallback (offline)" line when no key is set.
- **`--no-skill` / `--offline` flags:** `--no-skill` = the eval mechanism (scored on the Investigator);
  `--offline` = replay + cached fixtures (the demo must not depend on network).
- **`evals/evals.json` + root `benchmark.json`** — graded by exact name. Don't rename.
- **ADLC worksheet + routing table** — keep capturing live; the Synthesizer counts as the "iterate" story.

## The demo we're tuning toward
3-min screen recording: map of Boston, planes moving, planted anomalies on a KNOWN schedule —
an investigable event ~every 20s (zoom-in → verdict → zoom-out), one simultaneous pileup so the
watcher's prioritization shows, a multi-plane cluster ~2:00 so the Synthesizer's situation banner is the
finish. Runs `--offline` off the planted capture. Jesse hand-tunes timings on the day.

## Data on hand
`data/flightwatch-boston-raw-2026-06-22.jsonl` — midday Boston, ~90 frames, ~10 airborne avg. Densest
window: frames 36–53. Hero candidates: N53569, UAL1117, N9905F, DAL2351. Real captures have NO emergency
squawks — those are PLANTED by the eval planting script (its config doubles as the eval answer key).

## Judging (80 pts)
- **Shippability/conformance (25):** runs; skills pass `agentskills validate`; public repo + README + MIT.
- **ADLC discipline (20):** completed worksheet, ≥1 evaluate/observe loop.
- **Lane merit (20):** 3 context scopes (wide-shallow watcher / narrow-deep investigator / wide-temporal
  synthesizer), file-bus delegation, per-agent model routing.
- **Skill quality (15):** GATED by the eval delta.
