# Track E — Eval · owns `evals/`

> Paste this whole file as the opening prompt in the Track E worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane.
> ★ You own the EVAL GATE — the whole game. Converge FIRST with B and C, before any polish. ★

## Lane rules (non-negotiable)
- Work **only** in `evals/` (plus emit `benchmark.json` at repo root — see below). Never touch another track's dir or `contracts/` (frozen).
- Build against the frozen `detect(frame, buffer) -> [flag]` signature + `contracts/fixtures`. Ruby. **No database.**
- You are DONE when your self-test passes in isolation.

## What you build (three things)
### 1. Planting script + scenario CONFIG (the config IS the answer key)
`raw capture + scenario config → planted copy`. **Plant against a COPY, never the raw.** Output: `data/flightwatch-boston-planted-2026-06-22.jsonl`. The config lists exactly which `icao24`s are anomalous and how — it doubles as the eval ground truth AND the demo replay.
- Example config: `{window:[30,110], plant:[{icao24:"a47597",rule:"emergency_squawk",squawk:7700,from_frame:50},{icao24:"a3689e",rule:"holding_pattern",from_frame:40},{icao24:"a358bd",rule:"going_dark",at_frame:70}]}`
- **Pacing to engineer into it:** an investigable event ~every **20s** (~8–9 total), **≥1 simultaneous pileup** (2–3 flags on the same beat incl. a 7700, so the watcher's prioritization is visible), and **one ~5-plane cluster** near KBOS as the climax (~1:30–2:00). Vary anomaly TYPES across the timeline.
- Densest window in the capture: **frames 36–53** (avg 11.6 airborne). Hero candidates: N53569, UAL1117, N9905F, DAL2351 (recognizable carrier for the 7700).

### 2. Gate A — Detector regression tests (deterministic, NOT the skill score)
Proof `detect.rb` fires correctly. No model involved. Run these FIRST — a failure here = bug in `detect.rb` (holding geometry: heading wraparound 359→1, buffer-window edges, is most bug-prone), not skill wiring.
- **Standalone unit test per rule** firing on its plant IN ISOLATION (emergency_squawk, rapid_descent, going_dark, holding_pattern).
- **Strict assertions:** correct rule + correct aircraft + flag fires AT/AFTER the plant frame (a going_dark flag at frame 10 must not satisfy a plant at frame 70).
- **Precision guard:** caught the planted N AND did not bury them in spurious flags on clean planes.
- Lean the reported capability delta on **going_dark + holding** (bare model 0/3); de-emphasize squawk (model ignores 7700 anyway) and descent (fragile). Report as a capability check, NOT the skill score.

### 3. ★ Gate B — Investigator skill-quality eval (THE SCORED ARTIFACT) ★
The Investigator is the ONE place the MODEL reasons. `detect.rb` runs in BOTH arms (it's code). Vary ONLY the `flight-investigation` SKILL.md knowledge.
- **Mechanism:** fixture flags with KNOWN-correct verdicts → run Investigator with-skill vs `--no-skill` → does its `assessment` match expected?
- **Cases (judgment, not threshold-circular):**
  - `7600` + METAR fog + on approach to KBOS → **benign** (routine lost-comms; bare model over-escalates).
  - `rapid_descent` = normal approach descent into KBOS → **benign** (bare model cries wolf).
  - `going_dark` mid-cruise over open water → **concern**; low on approach → **benign**.
  - `7700` + erratic + steep descent, no benign explanation → **emergency** (easy; don't lean the delta here).
- **Honest pre-warning:** the frontier model is already decent, so this delta may read SMALLER than a detector-vs-nothing delta. That's informative, not a failure. If small, push Track C to make the skill carry genuinely non-obvious knowledge. Do NOT reach back to the detector eval for a bigger-looking number.

## Scoring rules that apply to ANY arm (proven by live probe, not theory)
- **Strict rule-match**, never "a flag exists for plane X" (the noisy baseline gets false credit otherwise).
- **Precision guard** so a flag-everything baseline can't score.
- **Run the baseline N times at `temperature: 0`, report worst/median** — bare-model output is severely non-deterministic (3 runs → 3 contradictory results).
- **Parse defensively** — malformed JSON ~1 run in 3 (strip fences, strip stray trailing chars).

## Required output files (EXACT names — graded directly)
- **`evals/evals.json`** — the 2–3+ cases. Each = input + observable countable assertion + PASS/FAIL + evidence.
- **`benchmark.json`** (repo ROOT) — aggregated with-skill vs without-skill result + the delta.

## Synthesizer (when Track F exists)
Plant a coordinated multi-plane scenario (5 holds near KBOS); assert it names the situation.

## DONE when (self-test, in isolation)
- Gate A detector tests run **GREEN** (deterministic).
- Gate B prints a with-skill vs `--no-skill` **assessment-match delta** on the fixture cases.
- `evals/evals.json` and root `benchmark.json` emitted by those exact names.

> Prerequisite: the raw capture in `data/`. Coordinate the fixture flag/verdict shapes with `contracts/` (frozen) — don't invent your own.
