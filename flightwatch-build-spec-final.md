# Flight Watch: Multi-Agent Airspace Anomaly System

**Lane 3 entry. The Open Accelerator Agent Build Day, June 27 2026.**

> ## ⏱ DAY-OF LOGISTICS (read first — times changed, these are authoritative)
> - **11:00 AM — Team formation + lane declaration.** Register Lane 3 + the repo URL here. **Do NOT skip this** (eligibility).
> - **Build window: ~10:45 AM → 4:00 PM.** **4:00 PM is the HARD commit freeze** — final commit in, repo TAGGED. Nothing after counts. (Schedule once said 5:00/11:00; 4:00 PM is authoritative. Plan backward from it; be done ~3:45 to leave tag + final-validate buffer.)
> - **3:00 PM — Midpoint check** (optional ADLC "evaluate" checkpoint). Lines up with our eval gate.
> - **5:15 PM — finalist demos (top per lane). 5:55 PM — awards.**
> - **Lane 3 eligibility bars (hard):** ≥2 cooperating agents AND ≥2 separately-loaded skills (one skill = FAIL); an identifiable, demoable delegation mechanism; ADLC worksheet + model-selection rationale **across the agents**.
> - **Required eval artifacts by exact name:** `evals/evals.json` (2-3 cases) aggregated into `benchmark.json` at repo root, with-skill vs without-skill PASS/FAIL + delta.
> - **Repo:** public GitHub + README w/ setup + OSI license; NO secrets committed; `scripts/` egress reviewed.

A three-agent system (with a two-agent floor) that watches live aircraft over Boston, flags notable behavior by rule, has an AI investigate and explain each flag, and a third agent that names emergent situations across flags. Demoed on a real map. Built and eval'd on captured + planted data so the demo is guaranteed to fire on cue.

---

## The one-paragraph pitch (for the judges)

Three agents with three different scopes of context that no single agent can hold at once. The **Watcher** sees one frame of all planes at once and scans their telemetry (position, altitude, squawk code, vertical rate, etc.) for known trouble signs — an emergency squawk, a steep descent, a plane gone silent, a holding loop. When it spots one it writes a **flag** (a small record saying "this plane, this issue, right now"). The **Investigator** picks up each flagged plane — a **"hit"** is simply a plane that got flagged — and looks at it deeply: it pulls in extra context the Watcher never had (weather, nearest airport, the plane's recent track) and judges whether the flag is a real concern or benign. The **Synthesizer** sees all flags over time and names emergent situations a single plane could never reveal (five separate holds near one airport = a possible ground stop). The separation is the point: the cheap local model watches every plane constantly and cheaply, while the expensive frontier model only does the deep, costly reasoning on the few planes that got flagged — so cost scales with how many anomalies occur, not with how much traffic there is. The eval proves the skill-equipped system catches planted anomalies that the no-skill baseline misses.

---

## Why multi-agent (the answer to the inevitable challenge)

Not volume. A Boston bounding box is low-hundreds of planes and one agent could hold that. The real reason is **context isolation across three scopes**:

- Watcher context = wide and shallow (every plane, one frame, cheap)
- Investigator context = narrow and deep (one plane, plus weather/airport/track enrichment that would bloat the Watcher)
- Synthesizer context = wide and temporal (all flags over a window, to spot patterns)

Holding all three in one context turns it to mush. That is the irreducible advantage.

---

## Judge talking points (memorize these)

**On why multi-agent / what the delegation mechanism is:**
> "We use the file-based workspace as the delegation bus. The Watcher writes a flag file, which is what triggers the Investigator, which writes a verdict file. It is framework-agnostic, it let us route a different model per agent, and it let us build the whole thing in parallel because every agent just reads and writes JSON against a frozen contract."

Why this answer wins: it shows the seams instead of hiding them behind a framework's defaults. For a room that grades evidence over impressions, exposed seams you can explain are a strength, not a weakness.

**On why not LangChain Deep Agents (if asked):**
> "Deep Agents is a natural fit and we considered it. But our delegation is file-based, not in-process, so the agents do not need to share a framework or even a language. That decoupling is what made the parallel build and the per-agent model routing clean. The framework would have hidden the exact seam we wanted to put on display."

**On the model cascade:**
> "Cheap local Granite watches every tick on-device, so the constant work never leaves the machine and costs nothing. The frontier model only fires on a flagged plane, which is rare. Cost scales with anomalies, not with traffic."

**On the anomaly question (the trap):**
> "We do rule-based detection, not statistical. The knowledge lives in aviation convention, not a historical corpus, so we need no training data. The rules are the skill. The statistical-baseline version is the obvious next iteration, and it is in our ADLC iterate phase."

---

## Architecture

```
                 OpenSky /states/all  (Boston bbox, poll 5-10s)
                          |
                  [Capture + Replay harness]   <-- eval & demo run off this
                          |
              rolling buffer (in-memory, keyed by icao24, last N positions)
                          |
   AGENT 1: WATCHER  (local granite4:micro)
     - loads skill: flight-anomaly-rules
     - calls scripts/detect.rb on each tick
     - writes flags to shared workspace/
                          |
              shared file workspace (the "virtual filesystem")
                 flags/*.json   verdicts/*.json   situations/*.json
                          |
        +-----------------+------------------+
        |                                    |
   AGENT 2: INVESTIGATOR (frontier)     AGENT 3: SYNTHESIZER (frontier/mid) [build last]
     - triggered per flag                 - reads all flags + verdicts
     - loads skill: flight-investigation  - clusters mechanically (code)
     - pulls: track, METAR, airport,      - loads skill: airspace-situation
       aircraft type                      - names emergent situations
     - writes verdict per plane           - writes situation banner
        |                                    |
        +-----------------+------------------+
                          |
                  MAP UI (Leaflet + OSM)
            planes render, flagged go red, verdict popups, situation banner
```

---

## Framework & stack (IMPORTANT for coding agents)

**Build the agents in Ruby with RubyLLM. Do NOT default to Python or LangChain.**

Lane 3 names the LangChain Deep Agents SDK as a "natural fit," but it is not required. The rubric is framework-agnostic. This project is Ruby because that is the builder's fluency, and because the file-based delegation makes the framework irrelevant.

- **Agent runtime:** Ruby + RubyLLM. Each agent is a process that reads JSON from the workspace, calls an LLM via RubyLLM, and writes JSON back. The "harness" the rubric wants is the Ruby loop + tool-calls + file access.
- **Delegation:** the shared file workspace IS the delegation bus. No in-process sub-agent passing. The Watcher writing a flag file is what triggers the Investigator. This is why agents need not share a language or framework.
- **Model endpoints, both via RubyLLM:**
  - Watcher → local Ollama (`granite4:micro`) through its OpenAI-compatible endpoint (`http://localhost:11434/v1`).
  - Investigator / Synthesizer → Anthropic API (frontier).
- **The detect script:** `scripts/detect.rb` — write it in **Ruby** to keep the build one language. (Python is acceptable behind the SAME frozen `detect(frame, buffer) -> [flag]` signature if a builder strongly prefers it, but DEFAULT to Ruby. Pick one and do not mix.) The signature is frozen in `contracts/`; the language is an implementation detail behind it.
- **Skills are framework-neutral by spec.** SKILL.md files must pass `agentskills validate`. The validator checks file structure and frontmatter, not the runtime, so Ruby does not affect skill conformance. Separately confirm the Ruby harness actually loads and applies each skill (validator proves well-formed, not wired-up).

Coding agents: when you see "agent" in this spec, it means a Ruby process using RubyLLM, not a Python LangChain construct. Do not pull in deepagents or langchain.

---

## The three agents

### Agent 1: Watcher  `local granite4:micro via Ollama`
Runs every tick. An LLM-in-a-loop that calls a detection tool (`scripts/detect.rb` bundled in its skill), reviews the candidate list, and writes flags to the workspace. Detection itself is deterministic rule code; the agent orchestrates and decides what is worth writing.

**Detection rules (no historical data needed, see rung table below):**
- Emergency squawk: 7500 (hijack), 7600 (lost comms), 7700 (general emergency). Pure field read.
- Rapid descent: `vertical_rate` below the threshold. **Threshold: < -12 m/s (≈ -2360 ft/min).** Note OpenSky gives vertical_rate in m/s; convert at normalization. Pure field read.
- Going dark: gap in `last_contact` / `time_position` after prior contact. Buffer-based.
- Holding pattern: circling geometry from the plane's own recent track. Buffer-based. **Algorithm (starting values, tune):** track cumulative heading change across the buffer window; flag a hold when the plane accumulates ≥ ~270-360° of turning in a consistent direction within ~90-120s WHILE staying inside a small radius (~3 nm). The "stays in a small area while turning a lot" combo is what distinguishes a hold from a normal course change. This is the HARDEST rule — budget real time for it, and it's also your most reliable delta source (emergencies are rare/planted; holds are common).
- (Stretch) Altitude outlier vs peers in same area this frame. Snapshot-based.

**Why the watcher is an agent (and it earns it via prioritization):**
The watcher loops, calls the detection tool, reviews candidates, writes flags. Detection itself is deterministic code (a feature — the event rewards "deterministic work goes in scripts, not the model"). The watcher's genuine AI judgment is TRIAGE PRIORITIZATION: when multiple planes flag on the same beat, ONE investigator can only take one at a time, so the watcher ranks the queue. Ranking "which matters most" under ambiguity is a real call a small model makes better than a brittle if-else. This is the watcher's reason to be an AI, not a script.

**Prioritization ruleset (write this down so it's consistent, not improvised):** a two-tier hybrid — code guarantees the safety-critical ordering, the model breaks ties in the ambiguous middle.

- **Tier 1 — Emergencies (DETERMINISTIC code, model not involved):** emergency squawks always outrank everything, in fixed order: **7700 (general emergency) > 7500 (hijack) > 7600 (lost comms)**. This is life-safety; it must never depend on a small model's mood. Code sorts these to the front. (This is also what guarantees your demo's pileup beat — the 7700 is FIRST, every time.)
- **Tier 2 — Everything else (MODEL ranks, using these factors):** for non-emergency flags (rapid_descent, going_dark, holding_pattern, altitude_outlier), the watcher's model orders them by, roughly in priority:
  1. **Anomaly severity** — rapid_descent / going_dark (could indicate real trouble) over holding_pattern (often benign).
  2. **Proximity to risk** — over a populated area or close to the airport > over open water.
  3. **Freshness** — a brand-new flag > one already stale in the queue.
  4. **Detection confidence** — a clean, unambiguous trip > a marginal threshold cross.
- **The model's job is ONLY the Tier-2 ordering.** Tier 1 is code. This split keeps the demo-critical "7700 first" bulletproof while giving the model a real judgment role (ranking genuinely close calls) that justifies it being an AI.
- **Output:** the watcher writes flags with a `priority` rank (or writes them to the queue in ranked order) so the single investigator drains them highest-first.

**Concurrency model (RESOLVED):** ONE investigator, draining a queue the watcher prioritizes. The file bus decouples everything — the watcher never blocks on the investigator, it drops flags and keeps scanning. NOT unlimited parallel investigators (frontier calls cost money + rate-limit; and parallelism would make prioritization pointless). One investigator + prioritized queue is the coherent design.

**Demo beat (staged, not hoped-for):** plant 2-3 anomalies that fire on the SAME beat so the queue genuinely forms and the watcher visibly orders them (e.g. a 7700 and two lesser flags hit at once → watcher sends the 7700 first, guaranteed by Tier 1). This is realistic (a weather event makes several planes act up at once) AND it makes the prioritization visible on stage. Invisible cleverness scores nothing; this is engineered to be seen.

### Agent 2: Investigator  `frontier (Claude)`
Triggered only on a flag, so cost is bounded. Pulls enrichment the Watcher never saw, then writes a plain-language verdict: real concern vs benign, with reasoning.

**Enrichment sources:**
- Recent track (from rolling buffer; OpenSky `/tracks` is experimental, treat as backup)
- METAR weather at location (aviationweather.gov, free, no key)
- Nearest airport / what's underneath (OurAirports static CSV)
- Aircraft type (optional static lookup)

**STRETCH (only if time remains at the end):** research pulling the weather/flight enrichment via an **MCP server** instead of a direct API call. This is the ONE place MCP is not bolted-on, because enrichment is a real external boundary (unlike the file-bus delegation, which needs no MCP). Default is the plain API call. Do NOT spend core build time on this; it is an end-of-day "if there's time" experiment, not a requirement. The strongest entry can also just say it considered MCP and chose the simpler call.

### Agent 3: Synthesizer  `frontier or mid`  **[TARGET DESIGN · build last, after the 2-agent floor works]**
Reads all flags + verdicts in the workspace. Clustering is dumb code (N same-type flags in same area + time window = a cluster). **Clustering constants (starting values, tune):** a cluster = **≥3 related-type flags**, within **~10 nm** of each other, within a **~120s window**, near the same airport. The agent interprets the cluster: "5 holds + 2 go-arounds near KBOS = possible ground stop." Detection stays code, meaning stays model.

**Why this is now target, not optional:** the host's Lane 3 reference entry runs 4 agents + a hub. The 2-agent system clears the stated bar ("at least two cooperating agents and two skills"), but the showcased exemplar sits well above the bar, and Lane Merit rewards density that stays clean. The Synthesizer is also where the "whole > parts" demo beat lives (individually-minor flags compose into one named situation), which is exactly the cross-reference reveal the host showcases as a great demo. So build all three.

**The safety valve (unchanged):** the 2-agent system (Watcher + Investigator) remains a complete, shippable entry. The Synthesizer is built LAST, after the eval gate clears and the 2-agent system runs. If the clock truly runs out, you ship two agents and the Synthesizer becomes the ADLC "iterate" page. Target three; floor is two.

---

## The anomaly question, settled

Four rungs. You build the first three. No database, no training, no corpus.

| Rung | Baseline is | Needs history? | Example | In scope? |
|---|---|---|---|---|
| Pure rule | a fixed standard | No | squawk 7700 = emergency | YES |
| Self-relative | the plane's own recent track (buffer) | No | sharp deviation from own heading | YES |
| Snapshot-relative | other planes right now | No | off the altitude everyone else is flying | YES (stretch) |
| History-relative | a learned corpus | **Yes** | unusual traffic volume for a Tuesday | NO (name as ADLC "iterate") |

The rules carry the expertise that a historical database would otherwise have to teach. The rules ARE the skill. The honest limitation (rules only catch anticipated anomalies, not unknown-unknowns) is your ADLC iterate story, which scores rather than costs.

---

## Skills (agentskills.io conformant, 3 skills · target)

1. **`flight-anomaly-rules`** (Watcher): signatures, thresholds, squawk meanings, gotchas, `scripts/detect.rb`, output template for a flag.
2. **`flight-investigation`** (Investigator): investigation procedure, what to pull, how to weigh weather/airport context, benign-vs-real heuristics, verdict template.
3. **`airspace-situation`** (Synthesizer): clustering rules, situation templates (ground stop, weather diversion, runway closure). (Skill #3; if the clock runs out the floor is the first two.)

### Skill validation (HARD GATE, do not skip)

`agentskills validate ./skill` must pass on **every** skill before the repo is considered shippable. This is not optional polish. It is directly scored (Shippability & Spec Conformance, 25 pts) and it is one of the event's published success targets (≥90% of teams pass validation). A skill that does not validate forfeits points it otherwise earns for free.

Each skill must satisfy, and the validator checks:
- **`SKILL.md`** present with valid YAML frontmatter + Markdown body.
- **`name`**: 1–64 chars, lowercase + numbers + hyphens, **matches the directory name exactly** (`flight-anomaly-rules/` dir → `name: flight-anomaly-rules`). Mismatch is the most common validation failure.
- **`description`**: 1–1,024 chars, states *what* and *when*, includes trigger keywords.
- **Progressive disclosure / budget**: metadata ~100 tokens at startup; body **under 5,000 tokens / 500 lines**; heavy material lives in `references/` or `scripts/` and loads on demand, not inline. An over-long SKILL.md that blows the context budget is a named common-failure and can fail the budget check.
- **Optional dirs used correctly** if present: `scripts/`, `references/`, `assets/`.

When validation runs:
- **Per track, before that track is "done":** each skill-owning track (B owns `flight-anomaly-rules`, C owns `flight-investigation`, optional Synthesizer track owns `airspace-situation`) runs `agentskills validate` on its own skill as its definition-of-done. A track is not finished until its skill validates green.
- **At convergence:** run validation across all skills again on the merged repo, since a merge can move files.
- **Before commit freeze (4:00 PM HARD STOP):** final `agentskills validate` pass on every skill, as the last pre-submission check. Put this in the freeze checklist.

Separately (the validator does NOT check this): confirm the **Ruby harness actually loads and applies** each skill at runtime. Validation proves the skill is well-formed; it does not prove your agent uses it. Both must be true.

**Pre-Saturday:** confirm the validator is installed and runs. **NOTE: on this machine the command is `agentskills`, NOT `skills-ref`** (the package installs a binary named `agentskills`). So: `agentskills validate ./some-hello-skill`. The prep guide and older notes say `skills-ref` — ignore that, use `agentskills`. (Confirmed working pre-Saturday on a hello-skill.)

---

## Agent definition files (each agent gets one)

Following the host's own pattern (BriefingClaw: "every agent is a real SKILL.md under agents/"), each agent is not just code, it is also an instructions file that defines its identity. This is what IBM/TOA mean by an agent having its own md. Add one per agent in `agents/`.

**These are DISTINCT from the 3 validated skills in `skills/`:**
- `skills/*` = procedural knowledge the agents LOAD. Validated by `agentskills`. Carries the eval delta + skill-quality points.
- `agents/*.md` = the agent's IDENTITY: its system prompt and role. This is where the watcher's "you are a triage agent" instructions live, documented instead of buried in a Ruby string.

Each agent's definition file documents:
- **Role** — one line ("constant cheap triage; flags planes by rule").
- **System prompt / instructions** — the actual prompt the agent runs with.
- **Model** — watcher → granite4:micro (local); investigator → frontier; synthesizer → frontier/mid.
- **Skill(s) loaded** — watcher → flight-anomaly-rules; investigator → flight-investigation; synthesizer → airspace-situation.
- **I/O contract** — which workspace dirs it reads and writes (watcher writes `flags/`; investigator reads `flags/` writes `verdicts/`; synthesizer reads both writes `situations/`).

**Decision (plain doc vs validatable skill):** default to plain `AGENT.md` docs for the three agents, keeping `agentskills validate` focused on the 3 real procedural skills where the points are. If you want to mirror BriefingClaw exactly and have time, make each agent definition a conformant SKILL.md too (more conformant, more validation surface). Default = plain docs; upgrade only if time allows.

**Also (for the parallel build):** a root `AGENTS.md` documenting the whole system (the three agents, the file bus, the contracts) helps the conductor coding agents understand how the pieces fit. Cheap to write, and it is the convention coding agents look for.

---

## Eval (the scored artifact) — TWO artifacts, do not conflate them

**The trap we avoided (read this first):** the obvious eval — run the Watcher with-skill vs `--no-skill` and count flags — measures the WRONG thing. The Watcher's detection is deterministic `detect.rb`; the model does no detection. So "skill on vs off" there is just "did detect.rb run," a delta that is large by construction and proves only that Ruby runs. It is a detector smoke test, NOT a skill-quality score. (Confirmed by a live probe: bare granite was 0/4 on correct attribution AND failed noisy — it flagged clean planes and flagged planted planes for wrong reasons.) So the eval is split in two:

### Artifact 1 — Detector regression test (the Watcher's detection). NOT the skill score.
Proof that `detect.rb` fires correctly. A normal, deterministic test suite, no model involved.
- **Standalone unit tests:** each rule fires on its plant IN ISOLATION (emergency_squawk, rapid_descent, going_dark, holding_pattern). This lets you disambiguate a later zero: a failing unit test = bug in `detect.rb` (holding geometry — heading wraparound 359→1, buffer-window edges — is the most bug-prone), NOT skill wiring. Run these FIRST.
- **Strict assertions:** correct rule + correct aircraft + flag fires AT/AFTER the plant frame (a going_dark flag at frame 10 must not satisfy a plant at frame 70).
- **Precision guard:** caught the planted N AND did not bury them in spurious flags on clean planes.
- The detector-vs-bare-model capability delta is real (baseline 0/4) but lean it on **going_dark + holding** (probe: 0/3 bone-clean) and de-emphasize squawk (model ignores 7700 anyway) and descent (fragile — model is innumerate, a better model could erode it). Report it as a capability check, not the skill score.

### Artifact 2 — Skill-quality eval (the Investigator's `flight-investigation` skill). ★ THE SCORED ARTIFACT ★
The Investigator is the ONE place the MODEL actually reasons — it judges a flag benign vs concern vs emergency. `detect.rb` runs in BOTH arms (it is code; always runs). Vary ONLY the `flight-investigation` SKILL.md knowledge. The delta measures the skill's effect on what the model actually decides. Not circular, can surprise you, honest.
- **Mechanism:** fixture flags with KNOWN-correct verdicts → run Investigator with-skill vs `--no-skill` → does its `assessment` match the expected one?
- **Example cases (judgment, NOT threshold-circular):**
  - `7600` + METAR fog + on approach to KBOS → correct = **benign** (routine lost-comms). Bare model over-escalates.
  - `rapid_descent` that is a normal approach descent into KBOS → correct = **benign**. Bare model cries wolf.
  - `going_dark` mid-cruise over open water → correct = **concern**; going_dark low on approach → benign. Skill supplies the disambiguation.
  - `7700` + erratic + steep descent, no benign explanation → correct = **emergency** (easy case; both arms likely pass — don't lean the delta here).
- **Scoring:** assessment-match accuracy, with-skill vs `--no-skill`, run N times at temp 0, report worst/median.
- **Honest pre-warning:** the frontier model is already decent at aviation judgment, so this delta may read SMALLER than a detector-vs-nothing delta. That is informative, not a failure. If it is small, make `flight-investigation` carry genuinely non-obvious knowledge the base model lacks (specific KBOS approach procedures, squawk-context rules, local quirks, the benign-vs-real heuristics above). Do NOT reach back to the detector eval for a bigger-looking number.

### Scoring rules that apply to ANY arm (proven by the live probe, not theory)
- **Strict rule-match**, never "a flag exists for plane X" — the noisy baseline gets false credit otherwise.
- **Precision guard** so a flag-everything baseline can't score.
- **Run the baseline N times at `temperature: 0`, report worst/median** — bare-model output is severely non-deterministic (3 runs gave 3 contradictory results).
- **Parse defensively** — malformed JSON observed 1 run in 3 (stray trailing chars; strip fences).

### Required output files (EXACT names the judges look for)
- **`evals/evals.json`** — the 2-3 test cases (the rules ask for 2-3; have at least that). Each case = input + observable countable assertion + PASS/FAIL + evidence.
- **`benchmark.json`** (repo root) — the aggregated with-skill vs without-skill result + the delta.
These two filenames are graded directly; emit them by these exact names even though our design is richer.

### The two flags to build
- **`--no-skill`**: runs the identical pipeline with the skill NOT loaded. For the Investigator this is the scored mechanism; for the Watcher `detect.rb` still runs (it is code).
- **`--offline`**: forces the network-free path (replay + cached enrichment fixtures). Makes the captured-data demo a tested code path so no network hiccup betrays you on stage.

### The corrected hour-one gate (before any polish)
- **Gate A — detector unit tests GREEN** (deterministic, fast). Must pass; disambiguates any later zero.
- **Gate B — Investigator skill-quality delta is real** on the fixture verdict cases (the number that maps to Skill-Quality points).
Both run off FIXTURES (fixture flags + known-correct verdicts), so both run early without the full pipeline.

**Source data:** `flightwatch-boston-raw-2026-06-22.jsonl` → copy into `data/` at scaffold. Plant against a COPY, never the raw. Planted file: `flightwatch-boston-planted-2026-06-22.jsonl`. The planting config is also the detector test's answer key.

**Synthesizer:** plant a coordinated multi-plane scenario (5 holds near KBOS), assert it names the situation.

---

## Observe (ADLC): the evaluate → observe → iterate loop

**Post-spine work, NOT baseline.** This is layered on AFTER the 2-agent spine runs and the eval gate clears. It never blocks the floor and never competes with the eval gate for the early window. Wire it once real flags and verdicts are landing in `workspace/`.

**The event log.** Every agent appends one JSON line per action to `workspace/observe/run.jsonl`: `{ ts, agent, action, icao24, latency_ms, tokens, cost_usd, outcome }`. The agents already compute every one of these values for the routing table, so this is one logging line in each main loop, not new instrumentation. The routing table (the model-selection receipt) becomes a reduction over this log, not a separate accounting path: "we log every agent action; the routing table is the aggregate." One mechanism, two artifacts.

**The load-bearing signal: detection precision from the Investigator's verdicts.** This is the real evaluate → observe → iterate loop, and the one to prioritize. The Watcher flags; the Investigator judges some of those flags `benign`; that benign rate is an observed precision metric on the detection rules, read straight from `workspace/verdicts/` with zero new machinery. The loop, end to end: the eval proves the skill delta BEFORE deploy; the benign rate observes detection precision DURING operation; "the holding-pattern threshold produced N benign flags, tighten the turn-angle constant" is the iterate item that falls out of it. Grounded in the system's own output, not bolted on. This is the evaluate/observe loop the rubric asks for, so it is the part of observe that must exist.

**Opportunistic, NOT relied upon: degradation counters.** The resilience design already has the Investigator falling back to local and agents logging-and-skipping malformed input (see Agent resilience). Counting these ("investigator fell back to local 2x, watcher skipped 1 malformed vector") is honest observe evidence when it occurs. But a clean scripted demo on planted data may legitimately trigger none of them, and that is correct: a zero here is a truthful observation of healthy operation, not a missing artifact. Do NOT build the demo narrative around these counters firing, and do not treat a run of zeros as a gap. The benign-rate loop carries observe; the degradation counters are a bonus when present.

**Skip OTel / Phoenix / Langfuse.** The doc names OpenTelemetry into Arize Phoenix or Langfuse. It buys the same "we observe the system" evidence that the JSONL log plus the benign-rate signal already buy, at many times the setup cost. Name it on the ADLC iterate page as the production-grade observability upgrade. That turns the thing you are not building into a scoring line instead of a gap.

---

## Demo replay construction (how the 3-min run gets built)

The demo does NOT depend on a live sky. It plays a deterministic, pre-built replay where every anomaly is guaranteed to fire on cue. The sky during your 3-minute slot is irrelevant. Here is how that replay is assembled from the raw capture.

**The replay is just a JSONL file** (same format as the raw capture). The harness reads it frame-by-frame and feeds the watcher as if live. "Choosing what's in the demo" = choosing/editing that file. You are the editor.

Three decisions, and a scenario CONFIG that records them:
1. **Pick the window.** 15 min (~90 frames) is too long. Choose a ~2-3 min stretch with healthy airborne traffic. *Safe to let an AI/script pick this* — scanning frames for the segment with the most persistent airborne planes can't corrupt anything; output is just a start/end frame range.
2. **Cast the planes.** Within the window, pick specific `icao24`s that persist across enough frames to read on screen (a plane in 2 frames makes a lousy holding-pattern demo). *An AI can suggest candidates* (which icao24s are present throughout). Output: a list of planes + the role each plays.
3. **Plant via a deterministic script, NOT freeform AI editing.** The planting script takes the raw capture + a scenario config and writes the planted file. Example config: `{window:[30,110], plant:[{icao24:"a47597", rule:"emergency_squawk", squawk:7700, from_frame:50}, {icao24:"a3689e", rule:"holding_pattern", from_frame:40}, {icao24:"a358bd", rule:"going_dark", at_frame:70}]}`.

**Why a config + script, not "let the AI edit the JSON":** the config IS your eval answer key. It lists exactly which planes are anomalous and how, so you can score precision/recall against ground truth. If an AI freely rewrites the JSON, you lose the clean record of what changed and the eval goes fuzzy. So: AI helps AUTHOR the scenario (pick window, cast planes); the deterministic script APPLIES it. One artifact (the config) serves both the demo replay and the eval ground truth — build it once.

**Make the demo a scripted, rehearsable run.** One command plays the planted capture start-to-finish with anomalies on a KNOWN schedule, so you can rehearse the 3 minutes until it's clockwork and it runs identically every time. Run it with `--offline` so no network call can betray you on stage. A choreographed replay is the difference between a demo and a gamble.

**Pacing requirements for the planted schedule (engineer these into the config):**
- **An investigable event roughly every ~20 seconds.** The demo is a recording reviewers watch — dead air is death. Space the anomalies so there is a fresh flag → zoom-in → verdict → zoom-out beat about every 20s across the 3 minutes (so ~8-9 events total). Keeps the visual continuously interesting.
- **At least one SIMULTANEOUS pileup.** Plant 2-3 anomalies that fire on the SAME beat (e.g. a 7700 + two lesser flags) so the queue forms and the watcher's prioritization is visibly exercised — it sends the 7700 first. This is the moment that justifies the watcher being an AI; make sure it is on screen.
- **One multi-plane cluster for the Synthesizer** (~5 holds near KBOS) timed as the climax (e.g. ~1:30-2:00) so the situation banner drops as the big finish.
- Vary the anomaly TYPES across the timeline (squawk, descent, going-dark, hold) so the demo shows the full rule set, not the same event repeated.

Suggested rough schedule (tune to your window): single flags at ~0:15, ~0:35; a simultaneous pileup at ~0:55; single flags at ~1:15; the cluster building ~1:30-2:00 (banner ~2:00); a couple more singles ~2:20, ~2:40.

**Pre-Saturday (optional but high-value):** sit with the raw capture, pick the window, cast the planes, write the scenario config. That single config becomes both your eval answer key and your demo replay. If your one captured window turns out thin on persistent airborne planes, grab another capture or two at a busier hour first — cheap now, annoying to wish for on Saturday.

**Pre-Saturday (MUST-DO — retires the biggest unknown):** write a ~20-line Ruby smoke test that (a) calls `granite4:micro` through RubyLLM via the Ollama endpoint and asserts it returns parseable JSON, and (b) calls Anthropic through RubyLLM. The entire watcher depends on RubyLLM→Ollama→clean-JSON working; this is the single highest-risk unverified path in the build. 20 minutes now versus discovering a rough edge at 11:30 Saturday. If it's janky, you have time to fix or adjust before the day.

**Planting is a build-time SCRIPT, not an agent.** No "synthetic data agent" in the system — real captured planes with surgically planted anomalies are MORE convincing to judges than invented traffic, and a 4th agent for demo convenience dilutes the clean 3-agent story. Detection is code; planting is code too.

**Validate in hour one (corrected — see the Eval section):** run BOTH gates before anything visual. Gate A: `detect.rb` unit tests green (deterministic). Gate B: the Investigator's `flight-investigation` skill produces a real with-skill vs `--no-skill` delta on fixture verdict cases — THAT is the skill-quality number. Do NOT treat the Watcher's detect-on-vs-off as the skill score (it only proves detect.rb ran).

---

## Model-selection rationale (mandatory deliverable)

| Agent | Model | Frequency | Why |
|---|---|---|---|
| Watcher | local `granite4:micro` (Ollama) | every tick (high) | cheap mechanical filtering; non-reasoning model fits the dispatcher role; on-device keeps data local (the on-prem angle) |
| Investigator | frontier (Claude) | per flag (low) | hard judgment, quality matters, volume bounded |
| Synthesizer | frontier or mid | per window (low) | higher-order reasoning, runs rarely |

This is the cascade the prompt praises: cheap watches, expensive investigates. Quantify it: cost per 100 planes watched vs investigated. That is your "quantitative comparison where feasible."

### Print a routing table after every run (the model-selection RECEIPT)

The host's own Lane 3 reference entry prints a per-agent routing table to stderr after each run. This is the physical artifact that scores the 20 model-selection points: not a paragraph, a table. Build it. (Implementation note: the routing table is a reduction over the `workspace/observe/run.jsonl` event log from the Observe section, not a separate accounting path. Same data, aggregated.) After a run, emit:

```
agent         model           route                          tok (p+c)      $       s
watcher       granite4:micro  local/cheap                      0+0      0.0000   ...   (or per-tick avg)
investigator  claude (frontier) frontier/strong              ...+...   0.00xx   ...
synthesizer   claude (frontier) frontier/strong              ...+...   0.00xx   ...
TOTAL                                                         ...+...   0.00xx   ...
```

Two things to copy from the reference exactly:
- **Cost scales with anomalies, not traffic.** The watcher row should show near-zero cost across a whole replay; the investigator/synthesizer rows show real tokens/$ but fire rarely. That contrast IS the cascade argument, made visible.
- **Graceful fallback, stated out loud in the table.** If the frontier key is missing or unreachable (e.g. the offline demo path), the investigator falls back to local and the route column says so: `frontier→local fallback (offline)`. Do not crash. The honest fallback line is something judges reward, and it makes the offline demo robust.

Put the with-frontier-key vs offline-fallback before/after into `MODEL_SELECTION.md`.

---

## Accounts & setup

| Thing | Account? | Cost | Status |
|---|---|---|---|
| OpenSky API client (OAuth2 client_id/secret) | yes | free | **DONE** — credentials.json in hand, authenticated call to Boston bbox confirmed returning data |
| Local model `granite4:micro` (Ollama) | no | free | **DONE** — Ollama on Mac, ~2GB. This is the model the TOA starter repo targets. |
| Anthropic API key | have it | $50 event credits | done |
| Map: Leaflet + OpenStreetMap tiles | **no** | free | day-of, trivial |
| Weather: aviationweather.gov METAR | no | free, no key | day-of |
| Airports: OurAirports CSV | no | free download | day-of |
| `agentskills` validator (NOT skills-ref) | no | free | before Saturday — confirmed working |
| Public GitHub repo + MIT license | yes (have) | free | day-of |
| Capture slice to JSONL (airborne traffic) | n/a | free | **DONE** — `flightwatch-boston-raw-2026-06-22.jsonl`, ~38-41 planes/frame, 8-10 airborne, 15 min @ 10s. Lives in the builder's local `~/Documents/` until the repo exists; copy into `data/` (or `contracts/fixtures/`) at scaffold time. This is the RAW source, do not modify it; planted versions are separate files. |

**Do NOT use Google Maps.** Requires billing + card, meters past free tier, live-demo liability. Leaflet + OSM is free and zero-setup.

OpenSky notes (confirmed working):
- Model is `granite4:micro` on Ollama (not Gemma). Apache 2.0, tool-calling + JSON output, non-reasoning — matches the Watcher's dispatcher role exactly. The deliberation lives in the frontier Investigator.
- **Auth is Ruby (NOT the Python binding).** Track A writes its own OAuth2 client-credentials exchange in Ruby: read client_id/secret from `.env` (or the credentials JSON), POST to the token endpoint, cache the bearer token, refresh it before the 30-min expiry. Do NOT reference any Python `TokenManager` — there is no Python in the agent stack. A plain Ruby HTTP call (Net::HTTP or Faraday) is all it takes. **`credentials.json` / `.env` must be gitignored** — never push the client_secret.
- Token endpoint: `https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token`. Token expires every 30 min; your Ruby auth caches it and refreshes before expiry — don't hand-paste tokens in code.
- Boston bbox confirmed: `lamin=42.2 lomin=-71.2 lamax=42.5 lomax=-70.9`.
- `/states/all` returns arrays-of-arrays, 18 fields, mapped by index (field order is fixed). See the AUTHORITATIVE field-index map in Phase 0 contracts. Key ones: 8=on_ground, 11=vertical_rate (m/s), 14=squawk (NOT 15).
- **Gotcha for detect.rb:** filter ground traffic. Planes parked/taxiing at Logan come back with `on_ground=true`, velocity ~0, and null altitude. They are not anomalies. Handle on-ground separately or a parked plane will trip your rules.
- Auth is OAuth2 client credentials only (basic auth retired March 2026). Anonymous access works but is rate-limited harder — fine for dev against the live endpoint, but the authenticated client gives headroom so credits don't run out mid-build.

---

## Build plan: contract-first parallelism (for conductor.build)

The thing that makes parallel agentic builds fail is integration: agents build for hours against assumptions about each other, then collide at merge. The fix is **no connector agent**. Lock the data contracts first, then every track builds against the contract (and against sample fixtures), not against another track's code. They converge at the end because they all targeted the same shapes.

### Cross-cutting build rules (apply to EVERY track)

**Rolling buffer sizing (Track A, used by B).** "Last N positions" is concretely: keep the last **~60 frames per plane** (~5-10 min at the poll rate) — enough track history for holding-pattern (needs the turn arc) and going-dark, not so much that memory grows unbounded. **Evict a plane ~5 min after its last contact** (after going-dark has had its chance to fire). Starting values; tune.

**Agent resilience (every agent wraps its main loop).** A build-day run must not die on one bad input. Each agent logs-and-skips rather than crashing: the watcher skips a malformed state vector (bad/missing field) and keeps scanning; the investigator on a frontier-call failure falls back to local (per the routing story) or writes a `"could not assess"` verdict; the synthesizer tolerates an empty/partial workspace. Agents stay UP. (`--offline` covers network; this covers everything else.)

**Contract enforcement (catch drift before integration).** Put a tiny shared schema-check helper in `contracts/` (e.g. `contracts/validate.rb`) that checks a flag/verdict/situation against its frozen schema. Each agent runs its output through it BEFORE writing to `workspace/`. Cheap, and it catches a drifted field name at the source instead of at Phase-2 integration. Fixtures and real outputs pass the same check.

**UI ↔ agents bridge (both directions go through the file bus, NOT HTTP between processes).** The Rails UI and the agents are separate processes; they communicate ONLY through `workspace/`, same as the agents do with each other. Two directions:
- **Agents → UI (display):** the Rails app **watches `workspace/`** with a file-watcher (the `listen` gem). When a new flag/verdict/situation file appears, the watcher fires the Action Cable broadcast to the browser. The agents stay dumb — they just write files; Rails is just another reader of the bus that happens to push to the browser. (Do NOT have agents POST to a Rails endpoint — that couples agents to the UI and breaks the decoupling.)
- **UI → agents (the real-time/demo toggle):** the UI writes a tiny control file `workspace/control/mode.json` (`{"source":"realtime"}` or `{"source":"demo"}`). Track A's frame producer reads that control file each tick and pulls from the live OpenSky poll or the replay file accordingly. No process restart, no UI→agent HTTP call. The watcher never knows the source changed — it just receives frames. This keeps the toggle on the same file bus as everything else.

This is the seam most likely to bite at integration if undefined. Both directions = files in `workspace/`. One mechanism, defensible to a judge as the same decoupling story extended to the UI.

**Tests as you build (NOT bolted on at the end).** A test suite is concrete ADLC "evaluate/observe" evidence and reads as "engineered like a product, not a demo hack" — exactly what this event rewards. But tests written last, under pressure, are shallow and the first thing cut. So:
- **Each track writes its done-condition as an actual test FILE during the build**, not a by-hand check. The done-conditions are already specified per track — turning "I verified this passes" into "here is the test that proves it" is nearly free and happens while context is fresh. (e.g. Track C: a test that drops a fixture flag and asserts a schema-valid verdict appears.)
- **Aim for a handful of MEANINGFUL tests, not coverage theater.** Judges score "is this a product," not coverage %. Tests that prove the contracts hold and each track meets its done-condition say "product" louder than 200 trivial unit tests. Do NOT chase exhaustive unit coverage — diminishing rubric return.
- **The one end-to-end test lives in Phase 2** (see Integration). It is both a scoring artifact and your demo insurance.

**ADLC worksheet as LIVE CAPTURE (not a freeze-time task).** Same logic as the tests above: do not reconstruct the worksheet from memory at 4:55. Open the blank template at kickoff. Scope and design fill in the first half hour, because they are already decided (the spec IS the design doc; transcribing decided design is not cheating). Then write the one line per phase AS you hit each milestone: build as each track lands, evaluate when the eval gate clears, observe when you watch it run and read the benign rate, iterate the moment you hit something you would change. This documents the lifecycle as you actually live it (the real point of the worksheet) and kills the freeze-time scramble, WITHOUT pre-fabricating phases you have not lived yet. The back-half phases stay honest because you fill them at the moment they happen, not before. By commit freeze the worksheet is being closed out, not written.

### Phase 0 — Repo scaffold + lock the contracts (DO FIRST, together, ~30 min, NOT parallel)

This is the highest-leverage half hour of the day. Two things happen here.

**0a. Scaffold the repo** (this is the real "step one," not `rails new` at the root):
```
flight-watch/
  contracts/        # frozen schemas + fixtures (Phase 0 output)
  data/             # Track A: capture, replay, buffer
  agents/           # Tracks B/C: watcher.rb, investigator.rb (+ synthesizer.rb optional)
  skills/           # the SKILL.md dirs
  enrichment/       # Track C: METAR, airports
  ui/               # Track D: stripped Rails + Action Cable + Leaflet
  evals/            # Track E: plant + score
  workspace/        # the runtime delegation bus: flags/ verdicts/ situations/ tracks/ control/ (gitignored)
  .gitignore        # credentials.json, workspace/, .env, tmp/
```
Rails is NOT the repo root. It lives only in `ui/`. The agents are standalone Ruby processes in `agents/`. They communicate through `workspace/`, not through Rails.

**0b. Lock the contracts.** Produce the schemas below plus one sample file each, and a tiny sample workspace. **After Phase 0, `contracts/` is frozen.** Any track needing a contract change is a STOP-and-renegotiate event, never a silent edit, because a silent schema change is exactly what breaks the merge.

The seams (the only things tracks share):

**ALL timestamps are epoch SECONDS (integer), never milliseconds.** `ts`, `last_contact`, `flag_ts` are all epoch seconds, matching OpenSky. The going-dark rule computes `frame.ts - aircraft.last_contact` in seconds; if any piece treats one as ms the gap math breaks silently.

**Normalized frame** (one polling tick, OpenSky arrays decoded into named fields so nobody downstream juggles indices):
```json
{ "ts": 1782141713,
  "aircraft": [
    { "icao24": "a47597", "callsign": "DAL1398", "lat": 42.3628, "lon": -71.0213,
      "baro_alt_ft": null, "velocity_kt": 0, "heading": 253.12, "vert_rate_fpm": null,
      "on_ground": true, "squawk": null, "last_contact": 1782141657 } ] }
```

**Flag** (Watcher writes to `workspace/flags/{icao24}-{ts}.json`):
```json
{ "icao24": "a47597", "ts": 1782141713, "rule": "emergency_squawk",
  "severity": "high", "lat": 42.36, "lon": -71.02,
  "evidence": { "squawk": "7700" } }
```
`rule` is one of: `emergency_squawk | rapid_descent | going_dark | holding_pattern | altitude_outlier`.

**Verdict** (Investigator writes to `workspace/verdicts/{icao24}-{ts}.json`):
```json
{ "icao24": "a47597", "flag_ts": 1782141713, "assessment": "benign|concern|emergency",
  "confidence": 0.0, "summary": "one-line plain-language explanation",
  "enrichment": { "metar": "...", "nearest_airport": "KBOS", "aircraft_type": "..." } }
```

**Situation** (Synthesizer writes to `workspace/situations/{id}.json`, optional):
```json
{ "id": "...", "ts": 1782141713, "kind": "ground_stop|weather_diversion|runway_closure",
  "airport": "KBOS", "icao24s": ["...","..."], "summary": "..." }
```

Also freeze in Phase 0: the Boston bbox and the `detect(frame, buffer) -> [flag]` function signature, plus the OpenSky field-index map below.

**OpenSky `/states/all` field-index map (AUTHORITATIVE — verified against docs, do NOT read from memory):**
```
0  icao24          str    transponder hex id
1  callsign        str    nullable
2  origin_country  str
3  time_position   int    epoch secs of last position report; null if none in 15s
4  last_contact    int    epoch secs of last message  <-- going-dark uses this
5  longitude       float  WGS-84 deg; nullable
6  latitude        float  WGS-84 deg; nullable
7  baro_altitude   float  METERS; nullable
8  on_ground       bool   true = surface  <-- filter these out
9  velocity        float  m/s over ground
10 true_track      float  heading deg CW from north
11 vertical_rate   float  M/S, positive = climb  <-- steep-descent uses this
12 sensors         int[]  usually null
13 geo_altitude    float  METERS; nullable
14 squawk          str    THE TRANSPONDER CODE. 7500/7600/7700 live HERE.
15 spi             bool   special-purpose indicator — NOT the squawk
16 position_source int
17 category        int    only if requested
```

**Burned-in lessons (these caused/avoided real bugs in the captured data):**
- **Squawk is index 14, NOT 15.** Index 15 is the `spi` boolean. Reading 15 returns `true`/`false`, so the emergency rule silently never fires. This is the single most important index in the build — the hero 7700 rule depends on it. Verify against real captured data before trusting it.
- **Units: vertical_rate (11) and both altitudes (7, 13) are METRIC.** vertical_rate is m/s, altitudes are meters. Aviation talks in ft and ft/min. Convert ONCE at normalization or every threshold is nonsense. Steep-descent starting threshold ~ -12 m/s (≈ -2360 ft/min).
- **Going-dark is a staleness signal, not a vanishing row.** OpenSky keeps emitting a state vector for ~300s after last contact. So detect going-dark as a growing gap between the frame's top-level `time` and the plane's `last_contact` (index 4), not as the plane disappearing from the array.
- **Real captures contain NO emergency squawks** (they're rare). Steep descents DO occur naturally (saw DAL2479 ≈ -2368 ft/min, DAL243 ≈ -2431 ft/min in capture 1). So emergencies are planted; the descent rule has real validation data.

**Chosen demo source:** `flightwatch-boston-raw-2026-06-22.jsonl` (the midday capture). It beat the evening hour on density (avg 10.1 airborne/frame vs 7.2). Densest ~3-min window: **frames 36-53, avg 11.6 airborne** — build the demo scenario there. Good hero-plane candidates (high airborne persistence): N53569, UAL1117, N9905F, and DAL2351 (recognizable mainline carrier for the 7700).

### Phase 1 — Parallel tracks (each owns its own directory, builds against fixtures)

Directory ownership so worktrees don't collide. Nobody edits another track's dir, and nobody edits `contracts/`. **Each track below has a paste-ready kickoff brief and a DONE-when. Paste the brief into that Conductor worktree as its opening prompt.**

Three rules apply to EVERY track: (1) stay in your directory, never touch another track's or `contracts/`; (2) build against the frozen `contracts/fixtures`, not against other tracks (they don't exist in your worktree); (3) you are DONE when your self-test passes in isolation. Stack: Ruby + RubyLLM (NOT Python/LangChain), no database, agents talk only through the `workspace/` file bus, validator is `agentskills`.

| Track | Owns | Builds against |
|---|---|---|
| A — Data | `data/` | live OpenSky + captured JSONL |
| B — Detection + Watcher | `skills/flight-anomaly-rules/`, `agents/watcher.rb` | synthetic frames + sample flags |
| C — Investigator | `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/` | sample flags from fixtures |
| D — UI (stripped Rails) | `ui/` | sample workspace fixtures |
| E — Eval | `evals/` | captured JSONL + `detect` signature |
| F — Synthesizer (build last) | `agents/synthesizer.rb`, `skills/airspace-situation/` | flag + verdict fixtures |

---

#### Track A — Data · owns `data/`
**KICKOFF (paste into worktree):** *Rules: stay in `data/` only; never touch another track's dir or `contracts/` (frozen); build against `contracts/fixtures`, not other tracks; Ruby (no Python/LangChain); no database; agents talk only via the `workspace/` file bus. You are DONE when the self-test below passes in isolation.* — Build the data layer in `data/`. OpenSky OAuth2 token manager (auto-refresh, 30-min expiry); poll `/states/all` on the Boston bbox 42.2/-71.2/42.5/-70.9; normalize the array-of-arrays into the `frame` contract USING the frozen field-index map (squawk=14, vert_rate=11 in m/s, on_ground=8, last_contact=4 — convert metric→ft/ft-min at normalization); an in-memory rolling buffer keyed by icao24 holding each plane's last N positions; a replay harness that reads `data/flightwatch-boston-raw-2026-06-22.jsonl` and emits frames in sequence as if live.
**DONE when:** normalizer run on the raw capture emits frames that validate against the `frame` schema; buffer returns a correct recent-track for a queried icao24; replay harness plays the raw file frame-by-frame. Verified with no other track.

#### Track B — Detection + Watcher · owns `skills/flight-anomaly-rules/`, `agents/watcher.rb`
**KICKOFF (paste into worktree):** *Rules: stay in `skills/flight-anomaly-rules/` and `agents/watcher.rb` only; never touch another track's dir or `contracts/` (frozen); build against `contracts/fixtures`; Ruby + RubyLLM (no Python/LangChain — except detect may optionally be Python behind the frozen signature); no database; agents talk only via the `workspace/` file bus; validator is `agentskills`. DONE when the self-test below passes in isolation.* — Build `detect(frame, buffer) -> [flag]` as `scripts/detect.rb` (per the frozen signature) with rules: emergency_squawk (7500/7600/7700 at index 14), rapid_descent (vert_rate < -12 m/s), going_dark (growing gap between frame time and last_contact index 4), holding_pattern (circling geometry from the buffer). FILTER on_ground aircraft — never flag parked/taxiing planes. Write the `flight-anomaly-rules` SKILL.md (name matches dir, triggers, gotchas, flag output template, body <500 lines) bundling `scripts/detect.rb`. Build the Watcher agent (Ruby + RubyLLM → local granite4:micro via Ollama's OpenAI-compatible endpoint `http://localhost:11434/v1`): loops frames, calls detect, applies triage PRIORITIZATION when multiple planes flag on one beat (rank which the single investigator sees first), writes flags to `workspace/flags/`. Add a `--no-skill` flag (see "what --no-skill toggles" in the spec). Detection is deterministic CODE; the model does prioritization, not detection.
**DONE when:** sample fixtures + a frame with a planted 7700 make detect emit contract-valid flags for exactly the right planes and none for on-ground planes; `agentskills validate ./skills/flight-anomaly-rules` is GREEN; watcher writes those flags to `workspace/flags/`. Verified against fixtures.

**Watcher model-output handling (VERIFIED on granite4:micro pre-Saturday — do this):** the prioritization call returns clean JSON at `temperature: 0` (confirmed). To keep it reliable: (1) **pin the output shape in the prompt** with a concrete example — ask for exactly `{"order":["icao24", ...]}` and show it; small models follow a shown template far better than a description. (2) **Parse defensively anyway** — accept either a top-level array OR an `{"order":[...]}` wrapper, and map each element to its id whether it's a bare string or an object with an `icao24` key (live testing returned both shapes depending on prompt). (3) **Strip markdown fences** before parsing (didn't appear in testing, but standard small-model hygiene). (4) Run prioritization at **`temperature: 0`** for consistent rankings. Endpoint: Ollama OpenAI-compatible at `http://localhost:11434/v1`.

#### Track C — Investigator · owns `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/`
**KICKOFF (paste into worktree):** *Rules: stay in `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/` only; never touch another track's dir or `contracts/` (frozen); build against `contracts/fixtures`; Ruby + RubyLLM (no Python/LangChain); no database; agents talk only via the `workspace/` file bus; validator is `agentskills`. DONE when the self-test below passes in isolation.* — Build enrichment in `enrichment/`: METAR (aviationweather.gov, no key), nearest airport (OurAirports CSV), optional aircraft type — each auto-falls-back to a cached fixture on any failure. Write the `flight-investigation` SKILL.md (procedure, benign-vs-real heuristics, verdict template, name matches dir). Build the Investigator agent (Ruby + RubyLLM → frontier Claude via Anthropic API): ONE investigator, first-come-first-served, reads a flag, pulls enrichment, writes a contract-valid verdict to `workspace/verdicts/`. Add `--no-skill` and `--offline` (forces cached fixtures). STRETCH only-if-time: enrichment via an MCP server instead of direct API.
**DONE when:** dropping a sample flag fixture produces a schema-valid verdict in `workspace/verdicts/` with enrichment populated; `agentskills validate ./skills/flight-investigation` is GREEN; `--offline` works with no network. Verified with a fixture flag — real watcher not needed.

#### Track D — UI · owns `ui/` (stripped Rails + Action Cable + Leaflet + Tailwind)
**KICKOFF (paste into worktree):** *Rules: stay in `ui/` only; never touch another track's dir or `contracts/` (frozen); build against the `contracts/fixtures` sample workspace — you need ZERO real agents; no database; render from `workspace/` JSON. DONE when the self-test below passes in isolation.* — Build the UI in `ui/`. `rails new ui --skip-active-record` (standard Rails, NOT `--minimal`) — NO database, NO ActiveRecord, NO models (if you reach for `rails generate model`, STOP). Only `DashboardController#index` with `root "dashboard#index"`. Details below.
**DONE when:** pointed at the fixture workspace, the map renders planes at correct positions, a fixture flag reds a plane and flies the camera in, a fixture verdict pops and flies out, a fixture situation drops the top banner, the routing-table panel shows rows, the **Anomalies tab appends a fixture flag row and then fills that row in place when the matching fixture verdict lands, and the Synthesis tab renders fixture situations**, **switching tabs does not unmount the map (and returning to Map calls `invalidateSize`)**, and dark mode + the demo/real-time toggle work. All verified against fixtures, zero real agents.

Concrete Rails structure (build exactly this, nothing more):
- **`DashboardController#index`** is the single page. Route: `root "dashboard#index"`. The map lives on the dashboard index view.
- **Map:** Leaflet + OSM tiles, full-bleed in the **Map tab** (the default active tab; see Tabbed layout below).
- **Real-time / Demo-mode toggle:** switches the FRAME SOURCE the agents run against, via the control file `workspace/control/mode.json` (the UI writes it; Track A's producer reads it each tick). **Real-time** = live OpenSky poll. **Demo mode** = replay of the planted capture (`--offline`, scripted anomalies). Downstream is identical either way; only the frame source changes. (See "UI ↔ agents bridge" in Cross-cutting build rules.)
- **Demo flow (the cold open):** OPEN on real-time — "this is the traffic over Boston right now" — then toggle to demo mode and run the scripted scenario. Real-time proves it's live; demo delivers the anomalies. Build for this narrative.
- **Make the real-time open ROBUST:** (1) **pre-warm** — real-time already polling before you present, planes on screen at t=0. (2) **auto-fallback** — if a poll fails/empties, hold the most recent good frame instead of going blank. With both, opening on real-time is safe.
- **Live updates:** Rails watches `workspace/` with the `listen` gem; a new flag/verdict/situation file fires an `AirspaceChannel` (Action Cable) broadcast the index subscribes to, driving marker updates + camera choreography. (See "UI ↔ agents bridge.") Agents just write files; Rails does the watching and pushing.
- **Routing-table panel:** docked panel showing the live per-agent routing table (agent · model · route · tokens · $ · latency · TOTAL). Watcher row ≈ $0; investigator/synthesizer rows show real cost but fire rarely. This is the model-selection evidence, on screen.
- **Situation banner (Synthesizer output):** FULL-WIDTH bar across the TOP, drops in when a situation file lands in `workspace/situations/`. The demo CLIMAX: unmissable, distinct from the routing panel, **persistent once fired** with an entrance pulse. NOT a tab.
- **Styling: Tailwind** via `tailwindcss-rails`, **class-based dark mode** (`darkMode: 'class'`) with a toggle button, NOT OS-auto.
- **Dark-mode gotcha:** OSM default tiles are light. Dark mode needs a **dark tile layer** (CartoDB dark_all) swapped in on the same toggle, or you get dark chrome around a bright map.

**Tabbed layout (NEW): Map · Anomalies · Synthesis**

The single index page gains a tab strip that switches the MAIN content region between three panels. Still one controller action, one route, no models. The point: each agent's work product gets a surface a judge can click through, which reinforces the multi-agent merit. Tabs are named for the USER concept, not the agent (e.g. "Anomalies", not "Investigator"), but each maps to an agent's output: **Map** surfaces the Watcher's live flagging (planes go red), **Anomalies** surfaces the Investigator's verdicts (with the Watcher's reason as context), **Synthesis** surfaces the Synthesizer's report.

- **Tab 1, Map (default, active on load):** the Leaflet map and all its choreography exactly as spec'd above. This is the demo stage.
- **Tab 2, Anomalies (the Investigator's surface, named for the user concept not the agent):** the investigated anomalies. Each entry pairs the WHY (the Watcher's reason for flagging: the rule that tripped, e.g. emergency_squawk / holding_pattern, plus severity and evidence) with the Investigator's verdict (assessment, confidence, plain-language summary, enrichment). This answers the question a user actually asks: what got flagged, and what did it turn out to be? Conceptually this is the Investigator's tab; the Watcher's flag is the context that explains why each anomaly is on the list.
- **Tab 3, Synthesis (Synthesizer report):** the ongoing situation report. Each situation file in `workspace/situations/` appends or updates the report. If the Synthesizer is cut (it builds last), this tab shows an empty state, consistent with the 2-agent floor. Do not let the tab imply the Synthesizer is mandatory.
- **Append mechanism (Turbo Streams over the SAME file bus):** reuse the existing `listen` watcher. When a flag file lands it already fires the `AirspaceChannel` map broadcast; ALSO call `Turbo::StreamsChannel.broadcast_append_to "anomalies", target: "anomaly-feed", partial: "..."` (same pattern for situations to `"synthesis"`). The view subscribes with `turbo_stream_from "anomalies"` / `"synthesis"`. No model needed: the `Turbo::StreamsChannel.broadcast_*_to` CLASS methods work without ActiveRecord. One file event drives both the map marker AND the tab feed. Agents stay dumb; Rails is still just a reader of `workspace/` that pushes.
- **Persistent chrome, NOT tabs:** the situation banner (top) and the routing-table panel (docked) stay visible across ALL tabs. The strip switches only the main region. Keeping the routing receipt and the climax banner always on screen is what you want in front of judges.
- **CRITICAL Leaflet gotcha, do NOT unmount the map on tab switch:** all three panels stay in the DOM; switch by toggling a visibility class, never by destroying/recreating the Map panel. A torn-down-and-rebuilt Leaflet map loses camera state, re-fetches tiles, and breaks the choreography. AND when the Map tab becomes visible again, call `map.invalidateSize()`: a Leaflet map sized while its container was `display:none` renders grey/half-tiled until invalidateSize runs. This is the single most likely tab bug. Wire invalidateSize on every return to Map.
- **The scripted demo runs on the Map tab.** flyTo choreography only reads while Map is visible, so the rehearsed 3-min run stays on Map. Anomalies and Synthesis are the "click through each agent" exploration: good for judges poking after the demo, and a strong optional closer (end by clicking Anomalies for the Watcher's full flag log, then Synthesis for the situation report, the receipts behind the map).
- **Empty states and order:** each feed needs a clean empty state (Anomalies is empty on a cold-open real-time start before any anomaly fires). Prepend newest-on-top so the latest is always visible without scrolling (or append with auto-scroll; UX call).
- **Anomalies feed mechanism (flag first, verdict fills in, one row):** when the Watcher writes a flag, append a row to the `anomalies` stream showing the WHY (rule, severity, evidence) via `broadcast_append_to`, dom_id keyed `{icao24}-{flag_ts}`. When the Investigator's verdict for that flag lands, REPLACE that row in place via `broadcast_replace_to` on the same dom_id, filling in the assessment and summary. Each row then tells the full story: flagged for X, investigated, found to be Y. While a flag is awaiting its verdict the row shows a pending state (the flag is real even before the verdict lands). Verdicts ALSO stay on the Map as the popup plus camera beat (unchanged, load-bearing); the Anomalies tab is the same verdicts as a readable log. There is NO separate "Investigations" tab: "Anomalies" IS the Investigator's surface, named for what the user wants to see, not for the agent.
- **Build command (resolved):** use `rails new ui --skip-active-record`, NOT `--minimal`. Standard Rails ships Action Cable and Hotwire/Turbo by default, so the map's `AirspaceChannel` and the Anomalies/Synthesis Turbo Stream feeds work out of the box with no re-adding. `--skip-active-record` keeps the no-database design intact (the file bus stays the source of truth). Just confirm `turbo-rails` is present after scaffold (it is, by default).

**Map visual assets (planes, rotation, color-as-state):**
- **Plane icon:** inline SVG in a Leaflet `divIcon` (NOT a PNG marker — SVG lets us rotate and recolor). A north-pointing top-down airplane SVG is in the assets folder (`airplane-svgrepo-com.svg`): single `<path>`, fill driven by a CSS class, nose points up (= heading 0 = north).
- **Rotation = direction of travel.** Rotate each plane by its `true_track` (heading) via a CSS `transform: rotate(Ndeg)` on the divIcon. Because the icon points north at 0°, rotation is the raw heading with NO offset (heading 90 → points east). This is what makes the map read as live air traffic instead of dots — high value, basically free since heading is in every frame.
- **Color encodes STATE, not identity** (deliberate — do NOT give each plane its own color). All normal planes share ONE calm neutral base (white / pale blue / gray). Color is reserved for meaning so the anomaly POPS:
  - normal/airborne → neutral base
  - flagged → **red** (the eye-snap moment; only works if normal planes are neutral)
  - under investigation (focus plane) → a distinct highlight (e.g. amber/cyan)
  - on-ground → muted/desaturated (and not flagged — see the on-ground filter)
  Recolor by overriding the SVG path's fill per state (single path, single fill = trivial). Variety comes from rotation, not color.
- **Airport marker:** a static marker for KBOS (Logan) so "ground stop at KBOS" is geographically legible and the synthesizer's cluster has an anchor.
- **Callsign labels:** show the callsign (e.g. "DAL303") as a small label on the FLAGGED / focus plane only, not all planes (all = text soup). Makes the verdict land harder ("DAL303 squawking 7700" with the named plane visible).

**Camera choreography (the investigation zoom):** Investigator picks up a plane → map flies in; verdict lands → flies back out. Makes the handoff *visible*. **Leaflet, not three.js** (2D geographic; Leaflet has native animated camera).
- **Core (~10 lines):** on flag broadcast → `map.flyTo([lat,lon], CLOSE_ZOOM)`; on verdict → `map.flyTo(OVERVIEW_CENTER, OVERVIEW_ZOOM)`.
- **Polish (sheddable, after eval gate):** dim other markers while zoomed; pulse ring on focus plane; verdict popup anchored to plane, hold, then fly out; flight-path polyline on the focused plane only.
- **Demo-pacing:** if the Investigator runs fast, add a ~1-2s dwell so the zoom registers on stage. UI-only, doesn't touch agents.

#### Track E — Eval · owns `evals/`
**KICKOFF (paste into worktree):** *Rules: stay in `evals/` only; never touch another track's dir or `contracts/` (frozen); build against the frozen `detect` signature + fixtures; Ruby; no database. DONE when the self-test below passes in isolation.* — Build in `evals/`. (1) A planting script: raw capture + scenario CONFIG → planted copy; the config IS the answer key (which icao24s are anomalous + how; pacing: event ~every 20s, ≥1 pileup, one ~5-plane cluster climax). (2) **Detector regression tests** (Gate A): each `detect.rb` rule fires on its plant IN ISOLATION; STRICT rule+aircraft+timing assertions; precision guard (no spurious flags on clean planes). (3) **Investigator skill-quality eval** (Gate B, the scored artifact): fixture flags with KNOWN-correct verdicts → run Investigator with-skill vs `--no-skill` → assessment-match accuracy, baseline run N times at temp 0, worst/median, parse defensively. See the Eval section for the case list. **OUTPUT EXACT FILES:** cases in `evals/evals.json` (2-3+), aggregated result + delta in `benchmark.json` at repo root — these names are graded directly.
**DONE when:** Gate A detector tests run green; Gate B prints a with-skill vs `--no-skill` assessment-match delta on the fixture cases. (Detector test = deterministic; skill delta = the scored number.)

#### Track F — Synthesizer · owns `agents/synthesizer.rb`, `skills/airspace-situation/` — BUILD LAST
**KICKOFF (paste into worktree):** *Rules: stay in `agents/synthesizer.rb` and `skills/airspace-situation/` only; never touch another track's dir or `contracts/` (frozen); build against `contracts/fixtures`; Ruby + RubyLLM; no database; agents talk only via the `workspace/` file bus; validator is `agentskills`. DONE when the self-test below passes in isolation.* — Build LAST, after the 2-agent system runs. Clustering code (N same-type flags, same area, within a time window = a cluster). Write the `airspace-situation` SKILL.md (clustering rules, situation templates: ground_stop / weather_diversion / runway_closure; name matches dir). Build the Synthesizer agent (Ruby + RubyLLM → frontier/mid): runs continuously, reads `workspace/flags/` + `workspace/verdicts/`, writes a contract-valid situation to `workspace/situations/`. No history needed — works on the current snapshot.
**DONE when:** fed a fixture cluster (5 holds near KBOS), it writes a schema-valid situation naming the ground stop; `agentskills validate ./skills/airspace-situation` is GREEN. Verified with fixtures.

**The key unlock:** Track D and Track E need ZERO real agents — they build against fixtures and just work when the real agents start writing real files. This is what replaces a "connector agent."

### Cross-cutting checkpoint (overrides parallelism): the eval gate

Tracks B, C, and E converge FIRST to clear the two gates BEFORE any polish. **Gate A:** `detect.rb` unit tests green (deterministic — needs B + E). **Gate B (the scored one):** the Investigator's `flight-investigation` skill shows a real with-skill vs `--no-skill` assessment-match delta on fixture verdict cases (needs C + E). Do not pour time into D's polish or the Synthesizer until both clear. NOTE: the Watcher's detect-on-vs-off is NOT the skill score (it only proves detect.rb ran); the scored skill delta lives on the Investigator, where the model actually reasons.

### Convergence order (after the gate clears)

1. B + C + E clear the two gates (detector tests + Investigator skill delta). **Gate.**
2. A feeds real replay frames into B. Now real flags land in the workspace.
3. C reads real flags, writes verdicts. **Two-agent system complete = a full Lane 3 entry.** (The spine.)
4. D renders the live workspace. The visual.
5. **Observe logging (post-spine).** Add the `workspace/observe/run.jsonl` append line to each running agent and wire the benign-rate read from `workspace/verdicts/`. Layered on the working spine, never ahead of it. See the Observe (ADLC) section. (The routing table then aggregates this log rather than computing separately.)
6. **Synthesizer** track (own dir `agents/synthesizer.rb` + `skills/airspace-situation/`) reads flags+verdicts, writes situations. The third agent + the climax banner. Build LAST, but build it: it brings you level with the host's reference entry and carries the "whole > parts" demo beat. If the clock truly runs out here, the 2-agent system already shipped (the floor) and this becomes the ADLC "iterate" page.
7. ADLC worksheet + model-selection writeup, **captured live through the day** (see the live-capture rule), not written at freeze. Mark the Synthesizer as the explicit "iterate" upside so the worksheet scores even if it is cut.

You can map your three-agent intuition onto this: UI is Track D, "building the agents" is Tracks B and C, and "connecting them" is not an agent at all, it is Phase 0 plus the convergence step. Lock the contracts and the connection builds itself.

### Phase 2 — Integration / convergence (a NAMED step, budget real time for it)

This is the "zip it all together" step. It is **NOT an agent** — it is a one-time human-driven build phase: merge the worktrees, swap fixtures for real components, run the whole pipeline end-to-end, fix the seams. Because of contract-first design it is BOUNDED (the pieces were built against the same frozen shapes, so they already mostly fit), but it is never zero. Budget for it; do not leave it to 4:55.

Steps:
1. **Merge worktrees** into one repo. Each track owned its own dir, so collisions are minimal by design — mostly clean merges. Nobody edited `contracts/` after freeze.
2. **Swap fixtures → real components.** UI stops reading sample workspace files and reads the live `workspace/` the agents write. Eval stops calling a stub and calls the real `detect`. This is the first time the real pieces touch.
3. **Run the full pipeline end-to-end once.** Replay → watcher flags → investigator verdicts → synthesizer situations → UI renders + banner + routing table. Watch for seam bugs (a drifted field name, a wrong path, a broadcast that doesn't land).
4. **Fix the seams.** There will be a few. This is the real work of this phase.
5. **Write ONE end-to-end pipeline test.** After the stitch, a single test that runs the full pipeline against a known planted input and asserts the whole chain: feed the planted capture → assert the expected flags appear in `workspace/flags/` → assert the expected verdicts in `workspace/verdicts/` → assert the cluster produces a situation in `workspace/situations/`. This exercises every agent + the bus end-to-end. It is a strong scoring artifact ("our system has an integration test") AND your demo insurance — if it passes, the demo works. Combined with the per-track tests written during the build, this is your test suite and your ADLC evaluate/observe evidence.

**Protect this:** converge EARLIER than feels necessary. Get a working end-to-end pipeline before polishing, so the last hour is tightening, not discovering. The eval gate (B+E) is deliberately the FIRST integration — it flushes seam bugs on the scored path before the rest piles on. Aim to have the 2-agent pipeline running end-to-end well before commit freeze; everything after is upside layered on a working spine.

**How the system actually runs (multiple processes at once):** the agents and the UI are SEPARATE processes that all run simultaneously and communicate through the `workspace/` directory. Practically: one terminal/process per agent (watcher, investigator, synthesizer) plus the Rails server for the UI, all pointed at the same repo's `workspace/`. Use a `Procfile` (foreman/overmind) or a `bin/dev`-style script so one command boots everything. Ollama must be running (`ollama serve`) for the watcher. Document the exact start command in the README — it is part of "deploy" on the ADLC worksheet.

**What `--no-skill` actually toggles (corrected):** the agent loads its SKILL.md at startup; `--no-skill` runs the identical pipeline WITHOUT loading it. The key correction: this is the SCORED mechanism only on the **Investigator**, because that is where the model reasons — with-skill vs no-skill changes its benign/concern/emergency judgment. On the **Watcher**, `detect.rb` is code and runs either way, so Watcher detect-on-vs-off only proves the detector ran (a capability/plumbing check, NOT the skill-quality score). Put the scored delta on the Investigator's `flight-investigation` skill.

### Commit-freeze checklist (run by ~3:45 PM — 4:00 PM is the HARD commit freeze)

**Lane 3 eligibility (hard bars — miss one = ineligible):**
- [ ] ≥2 cooperating agents present and actually cooperating (Watcher + Investigator is the floor).
- [ ] ≥2 separately-loaded skills present (NOT just two agents). `flight-anomaly-rules` + `flight-investigation` is the floor; one skill = FAIL.
- [ ] Delegation/composition mechanism is identifiable and demoable (point at the file bus + the visible flag→investigate→verdict handoff).
- [ ] Lane 3 declared + repo URL registered at the 11:00 AM team-formation step (do this in the morning, not at freeze).

**Skills (each one):**
- [ ] `agentskills validate` passes GREEN on every skill (`flight-anomaly-rules`, `flight-investigation`, +`airspace-situation` if built).
- [ ] `name` is lowercase/numbers/hyphens, 1-64 chars, matches the directory name.
- [ ] `description` states what AND when, includes trigger keywords, under 1,024 chars.
- [ ] Body under 5,000 tokens / 500 lines; heavy content in `references/`/`scripts/`/`assets/`.
- [ ] Each skill is actually loaded and applied by its Ruby agent at runtime (not just well-formed).

**Eval artifacts (EXACT names — graded directly):**
- [ ] `evals/evals.json` present, 2-3+ cases, observable countable assertions + PASS/FAIL + evidence.
- [ ] `benchmark.json` at repo root: aggregated with-skill vs without-skill + the delta.
- [ ] Test suite present: per-track tests + the one end-to-end pipeline test, passing.
- [ ] Observe artifacts: `workspace/observe/run.jsonl` written; benign-rate (Investigator verdicts vs Watcher flags) computed as the evaluate/observe loop. Degradation counters reported if any fired (zeros OK).

**Documentation:**
- [ ] Model-selection rationale written, covering EACH agent's model + why (cost/latency/quality), with the cost-per-tick cascade argument. Quantitative comparison included (routing table) since feasible.
- [ ] ADLC worksheet CLOSED OUT (captured live, one page per phase, ≥1 evaluate/observe loop). Synthesizer marked "iterate" if cut; OTel/Phoenix named as the observe upgrade on the iterate page.
- [ ] Routing table prints after a run (per-agent model/route/tokens/$/latency + TOTAL); watcher near-zero; fallback line shows when offline.

**Repo + shippability:**
- [ ] Public GitHub repo; README with SETUP instructions (the bin/dev start command); OSI-approved LICENSE file (MIT).
- [ ] NO secrets committed: `credentials.json`/`.env` gitignored — grep the history to be sure. `scripts/` egress reviewed (skill-security).
- [ ] OpenSky credited as data source in the README.
- [ ] Final commit pushed and **repo TAGGED before 4:00 PM.**

---

## What you demo

Map of Boston, planes moving live. A planted anomaly fires on cue: a plane goes red. The Investigator's verdict pops next to it ("squawking 7600 over KBOS in fog, likely routine lost-comms on approach, low concern"). Then the Synthesizer drops a banner naming a situation across multiple planes ("possible ground stop at KBOS, 5 aircraft") — the whole-greater-than-parts beat. Live feed runs alongside as the flourish. The red light fires off your planted replay data, not off hope that a real plane squawks 7700 while three judges watch. (If the Synthesizer was cut for time, the 2-agent demo still lands; the banner is the bonus.)

**Optional closer (the receipts):** after the Map run, click through the tabs to show each agent's work product directly. Anomalies = the investigated anomalies (each flag's reason paired with the Investigator's verdict); Synthesis = the Synthesizer's situation report. This makes "three agents, three scopes" tangible (the judge sees each agent's separate output, not just the composite on the map) and reinforces the Lane 3 multi-agent merit.
