# FlightWatch — agent orientation

You are one of several parallel agents building **FlightWatch** at a 6-hour hackathon
(The Open Accelerator Agent Build Day, Lane 3). Read this file, then read `flightwatch-build-spec.md`.
**When this file and the spec conflict, the spec wins** — it is the source of truth.

## ⚠️ Stay in your lane
You own exactly ONE lane (see the table below). Build only your lane's files. Do not touch
another lane's code, refactor across lanes, or "helpfully" fix things outside your scope —
another agent is in there right now. Everyone integrates through two things only:
**the frozen contracts** and **the `workspace/` file bus**. If your lane needs something from
another lane, build against the frozen contract/fixtures, not against their live code.

| Lane | Owner files | Responsibility |
|------|-------------|----------------|
| **A — Data** | `data/` | OpenSky capture, replay, rolling in-memory buffer, raw capture. Feeds normalized frames to B. |
| **B — Watcher** | `agents/watcher.rb`, `skills/flight-anomaly-rules/` | Deterministic rule detection → writes flag files. Local `granite4:micro`. |
| **C — Investigator** | `agents/investigator.rb`, `enrichment/`, `skills/flight-investigation/` | Judges each flag → writes verdict files. Frontier Claude. METAR + airport enrichment. |
| **D — UI** | `ui/` | Rails + Action Cable + Leaflet + Tailwind. Renders the bus live. No DB. |
| **E — Evals** | `evals/` | Plant anomalies + score. Owns the with-skill vs `--no-skill` delta. |
| **F — Synthesizer** | `agents/synthesizer.rb`, `skills/airspace-situation/` | Names situations across flags. Frontier. Build LAST. |

## What we're building, in one breath
3 agents over live Boston air traffic. **Watcher** flags planes by deterministic rule →
**Investigator** judges each flag → **Synthesizer** names situations across flags. Agents talk
ONLY through the shared `workspace/` file bus. A Rails + Leaflet UI renders it live. The demo runs
off a pre-recorded + planted capture (`--offline`), never the live sky.

## The one thing that matters most: the eval gate
A skill scores ONLY if it beats a no-skill baseline on evals. **That delta is the whole game.**
Before building anything pretty, prove the with-skill vs `--no-skill` delta is real and non-noisy.
If you're unsure what to do next, the answer is almost always "make the eval gate pass."

## Decisions already made — do NOT relitigate
- **Ruby + RubyLLM.** Not Python, not LangChain/Deep Agents. An "agent" = a Ruby process using
  RubyLLM. Don't `pip install` for agents. (`detect.*` may be Python — it's a bundled script behind a
  frozen signature.)
- **No database.** State = `workspace/` JSON + in-memory rolling buffer. No Postgres/ActiveRecord.
  Never `rails generate model`. (SQLite only if explicitly asked.)
- **Delegation is the file bus** — not in-process calls, not MCP, not sub-agents. Watcher writes a flag
  file → triggers Investigator → writes a verdict file → Synthesizer reads both. That's it.
- **Detection is deterministic code; judgment is the model.** The watcher detects via a script (fast,
  cheap, testable). The model does triage prioritization and the investigator/synthesizer reasoning.
  Never make the watcher "detect" with an LLM.
- **Simpler beats clever.** File bus over MCP, no DB, one investigator. The 2-agent system is a complete
  entry; everything past it is upside on a clock. Don't add agents/frameworks/services to look fancy.

## Phase 0 contracts are FROZEN — treat as law
Everything builds against the frozen frame/flag/verdict/situation schemas, the OpenSky field-index map,
and the fixtures in `contracts/`. A silent contract change is the #1 way to break the parallel build.
If you think a contract must change: **stop and renegotiate**, do not edit it quietly.

## TRAPS already hit — every lane respect these
- **Squawk is field index 14, NOT 15.** Index 15 is `spi` (boolean). Reading 15 silently breaks the
  emergency-squawk rule — the hero rule. Verify against real data.
- **OpenSky units are METRIC.** `vertical_rate` m/s, altitudes meters. Convert to ft / ft/min **once**
  at frame normalization, or every threshold is nonsense.
- **Filter on-ground aircraft.** Parked/taxiing at Logan (`on_ground=true`, velocity~0, null alt) must
  never flag.
- **"Going dark" is staleness, not a missing row.** OpenSky keeps emitting ~300s after last contact.
  Detect a growing gap between frame `time` and the plane's `last_contact` (index 4).
- **Validator command is `agentskills`, NOT `skills-ref`.** Use `agentskills validate ./skills/<name>`.
- **OpenSky auth = OAuth2 client-credentials**, token expires every 30 min — auto-refresh, don't paste
  tokens. Stay on the laptop's IP (cloud IPs blocked). `credentials.json` + `.env` stay gitignored.

## Two artifacts that score points and are easy to forget
- **Routing table:** after every run, print a per-agent table (agent · model · route · tokens · $ ·
  latency · TOTAL). Watcher ≈ $0; investigator/synthesizer show real cost but fire rarely. Show in print
  AND as a dashboard panel. Include a graceful "frontier→local fallback (offline)" line when no key set.
- **`--no-skill` and `--offline` flags:** `--no-skill` runs with the skill unloaded (the eval mechanism);
  `--offline` forces replay + cached fixtures (the demo must not depend on network).
- **ADLC worksheet + routing table throughout, not at the end.** One page per phase, ≥1 evaluate/observe
  loop. Most teams skip it = easy points. Fill it AS YOU GO.

## The demo we're optimizing toward
3-min screen recording: map of Boston, planes moving, planted anomalies firing on a KNOWN schedule —
an investigable event ~every 20s (zoom-in → verdict → zoom-out), one simultaneous pileup so the
watcher's prioritization shows, a multi-plane cluster ~2:00 so the Synthesizer's situation banner is the
finish. Runs `--offline` off the planted capture. Jesse hand-tunes timings on the day — make the system
solid and fast enough to leave time to curate.

## Data on hand
`data/flightwatch-boston-raw-2026-06-22.jsonl` — midday Boston, ~90 frames, ~10 airborne avg. Densest
window: frames 36–53. Hero candidates: N53569, UAL1117, N9905F, DAL2351. Real captures have NO emergency
squawks — those are PLANTED by a build-time script driven by a config that doubles as the eval answer key.

## Judging (80 pts — optimize for this)
- **Shippability/conformance (25):** runs; skills pass `agentskills validate`; public repo + README +
  MIT license. Mechanical — don't drop them.
- **ADLC discipline (20):** completed worksheet with ≥1 evaluate/observe loop.
- **Lane merit (20):** novelty + soundness of the multi-agent orchestration — 3 context scopes
  (wide-shallow watcher / narrow-deep investigator / wide-temporal synthesizer), file-bus delegation,
  per-agent model routing.
- **Skill quality (15):** GATED by the eval delta. Real expertise, gotchas, output templates.
