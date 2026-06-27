# Track F — Synthesizer · owns `agents/synthesizer.rb`, `skills/airspace-situation/` — BUILD LAST

> Paste this whole file as the opening prompt in the Track F worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane.
> BUILD LAST — only after the 2-agent system (Watcher + Investigator) runs and the eval gate clears. The 2-agent system is already a complete entry; this is the third agent + the demo climax.

## Lane rules (non-negotiable)
- Work **only** in `agents/synthesizer.rb` and `skills/airspace-situation/`. Never touch another track's dir or `contracts/` (frozen).
- Build against `contracts/fixtures` (flag + verdict fixtures). Ruby + RubyLLM. **No database.** File bus only. Validator is `agentskills`.
- If a frozen contract seems wrong: **STOP and flag it.**
- You are DONE when your self-test passes in isolation.

## What you build
1. **Clustering code** (deterministic, no LLM): N same-type flags in the same area + time window = a cluster. **Starting constants (tune):** a cluster = **≥3 related-type flags**, within **~10 nm** of each other, within a **~120s window**, near the same airport. Detection stays code; meaning stays model.
2. **`airspace-situation` SKILL.md** — `name: airspace-situation` (must match dir), description with what+when+triggers, the clustering rules, and situation templates: **ground_stop / weather_diversion / runway_closure**. **Body < 5,000 tokens / 500 lines.** Must pass `agentskills validate ./skills/airspace-situation`.
3. **Synthesizer agent** (`agents/synthesizer.rb`, Ruby + RubyLLM → frontier/mid): runs continuously, reads `workspace/flags/` + `workspace/verdicts/`, clusters mechanically, then the model INTERPRETS the cluster ("5 holds + 2 go-arounds near KBOS = possible ground stop") and writes a contract-valid situation to `workspace/situations/`. No history needed — works on the current snapshot.

## Contracts
You READ flags (`workspace/flags/...`) and verdicts (`workspace/verdicts/...`).
You WRITE **situation** → `workspace/situations/{id}.json`:
```json
{ "id":"...","ts":1782141713,"kind":"ground_stop|weather_diversion|runway_closure",
  "airport":"KBOS","icao24s":["...","..."],"summary":"..." }
```
All timestamps epoch **seconds**. Validate output through `contracts/validate.rb` before writing.

## Resilience
Wrap the main loop: tolerate an empty/partial workspace; never crash. On a frontier-call failure, fall back to local or skip.

## DONE when (self-test, in isolation)
- Fed a fixture cluster (5 holds near KBOS), it writes a **schema-valid situation** naming the ground stop.
- `agentskills validate ./skills/airspace-situation` is **GREEN**.
- Verified with fixtures. Write it as an actual test FILE.

> This carries the "whole > parts" demo beat (individually-minor flags compose into one named situation = the climax banner). If the clock truly runs out, the 2-agent system already shipped and this becomes the ADLC "iterate" page.
