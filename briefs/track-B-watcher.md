# Track B — Detection + Watcher · owns `skills/flight-anomaly-rules/`, `agents/watcher.rb`

> Paste this whole file as the opening prompt in the Track B worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane.

## Lane rules (non-negotiable)
- Work **only** in `skills/flight-anomaly-rules/` and `agents/watcher.rb`. Never touch another track's dir or `contracts/` (frozen).
- Build against `contracts/fixtures` (synthetic frames + sample flags). Other tracks don't exist in your worktree.
- Ruby + RubyLLM (no Python/LangChain — **except** `detect` MAY be Python behind the frozen signature; default Ruby, don't mix). **No database.** File bus only. Validator is `agentskills`.
- If a frozen contract seems wrong: **STOP and flag it.**
- You are DONE when your self-test passes in isolation.

## What you build
1. **`detect(frame, buffer) -> [flag]`** as `skills/flight-anomaly-rules/scripts/detect.rb` (the frozen signature). **Deterministic CODE, no LLM.** Rules:
   - **emergency_squawk** — squawk ∈ {7500, 7600, 7700} at **index 14**. Pure field read.
   - **rapid_descent** — `vert_rate_fpm` below threshold ≈ **< −12 m/s (≈ −2360 ft/min)**. (Field already converted by Track A.)
   - **going_dark** — growing gap between frame `ts` and the plane's `last_contact` (index 4). Buffer-based.
   - **holding_pattern** — circling geometry from the buffer. **HARDEST rule, budget time.** Starting algorithm: accumulate heading change across the buffer window; flag when the plane turns **≥ ~270–360° consistent direction within ~90–120s WHILE staying inside ~3 nm**. The "turns a lot but stays put" combo is what separates a hold from a course change. (Watch heading wraparound 359°→1° and buffer-window edges — most bug-prone.)
   - (stretch) altitude_outlier vs peers this frame.
   - **FILTER `on_ground` aircraft — never flag parked/taxiing planes.**
2. **`flight-anomaly-rules` SKILL.md** — `name: flight-anomaly-rules` (must match dir), description with what+when+trigger keywords, signatures/thresholds/squawk-meanings/gotchas, the flag output template, bundles `scripts/detect.rb`. **Body < 5,000 tokens / 500 lines**; heavy material in `references/`/`scripts/`. Must pass `agentskills validate ./skills/flight-anomaly-rules`.
3. **Watcher agent** (`agents/watcher.rb`, Ruby + RubyLLM → local granite4:micro via Ollama OpenAI-compatible endpoint `http://localhost:11434/v1`): loops frames, calls `detect`, applies **triage prioritization** when multiple planes flag on one beat, writes flags to `workspace/flags/{icao24}-{ts}.json`. Add a **`--no-skill`** flag (runs the pipeline without loading the SKILL.md; `detect.rb` still runs — it's code).

## Prioritization ruleset (the watcher's reason to be an AI — write it down, don't improvise)
Two-tier hybrid:
- **Tier 1 — Emergencies = DETERMINISTIC code, model NOT involved.** Emergency squawks always outrank everything, fixed order: **7700 > 7500 > 7600**. Code sorts these to the front. (This guarantees the demo's "7700 first" pileup beat.)
- **Tier 2 — Everything else = the MODEL ranks** (rapid_descent / going_dark / holding_pattern / altitude_outlier), by: (1) anomaly severity (descent/going-dark > holding), (2) proximity to risk (populated/near-airport > open water), (3) freshness (new > stale), (4) detection confidence (clean trip > marginal).
- The model's job is **ONLY Tier-2 ordering.** Output flags with a `priority` rank (or in ranked order) so the single investigator drains highest-first.

## Watcher model-output handling (VERIFIED on granite4:micro — do this)
- **Pin the output shape in the prompt** with a concrete example — ask for exactly `{"order":["icao24", ...]}` and SHOW it. Small models follow a shown template far better than a description.
- **Parse defensively**: accept a top-level array OR an `{"order":[...]}` wrapper; map each element to its id whether it's a bare string or `{icao24:...}` object.
- **Strip markdown fences** before parsing.
- Run prioritization at **`temperature: 0`**.

## Contract you write
**Flag** → `workspace/flags/{icao24}-{ts}.json`:
```json
{ "icao24": "a47597", "ts": 1782141713, "rule": "emergency_squawk",
  "severity": "high", "lat": 42.36, "lon": -71.02, "evidence": { "squawk": "7700" } }
```
`rule` ∈ `emergency_squawk | rapid_descent | going_dark | holding_pattern | altitude_outlier`. All timestamps epoch **seconds**. Validate output through `contracts/validate.rb` before writing.

## Resilience
Wrap the main loop: skip a malformed state vector (bad/missing field) and keep scanning. Never crash on one bad input.

## DONE when (self-test, in isolation)
- Sample fixtures + a frame with a planted 7700 → `detect` emits contract-valid flags for exactly the right planes and **none for on-ground planes**.
- `agentskills validate ./skills/flight-anomaly-rules` is **GREEN**.
- Watcher writes those flags to `workspace/flags/`.
- Write these as actual test FILES.
