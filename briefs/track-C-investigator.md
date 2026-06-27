# Track C — Investigator · owns `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/`

> Paste this whole file as the opening prompt in the Track C worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane.
> ★ Your skill carries THE SCORED EVAL DELTA. Read the "skill must carry real knowledge" note below. ★

## Lane rules (non-negotiable)
- Work **only** in `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/`. Never touch another track's dir or `contracts/` (frozen).
- Build against `contracts/fixtures` (sample flags). Other tracks don't exist in your worktree.
- Ruby + RubyLLM (no Python/LangChain). **No database.** File bus only. Validator is `agentskills`.
- If a frozen contract seems wrong: **STOP and flag it.**
- You are DONE when your self-test passes in isolation.

## What you build
1. **Enrichment** (`enrichment/`), each auto-falling-back to a cached fixture on ANY failure:
   - **METAR** weather at the plane's location — aviationweather.gov (free, no key).
   - **Nearest airport / what's underneath** — OurAirports static CSV.
   - **Aircraft type** (optional) — static lookup.
2. **`flight-investigation` SKILL.md** — `name: flight-investigation` (must match dir), description with what+when+triggers, the investigation procedure, benign-vs-real heuristics, the verdict template. **Body < 5,000 tokens / 500 lines**; heavy material in `references/`. Must pass `agentskills validate ./skills/flight-investigation`.
3. **Investigator agent** (`agents/investigator.rb`, Ruby + RubyLLM → frontier Claude via Anthropic API): **ONE investigator, first-come-first-served**, reads a flag from `workspace/flags/`, pulls enrichment, writes a contract-valid verdict to `workspace/verdicts/`. Add **`--no-skill`** (runs without loading the SKILL.md — this is the SCORED mechanism) and **`--offline`** (forces cached enrichment fixtures, no network).
   - **STRETCH only-if-time:** enrichment via an MCP server instead of direct API. Default = the plain API call. Do not spend core time here.

## ★ The skill must carry REAL, non-obvious knowledge ★
This skill's with-skill vs `--no-skill` delta on the Investigator IS the scored artifact. The frontier model is already decent at aviation judgment, so a thin skill produces a small delta. Load the skill with knowledge the base model lacks: **specific KBOS approach procedures, squawk-context rules, local quirks, and the benign-vs-real heuristics below.** Do NOT lean on the detector eval for a bigger-looking number — this is the number that maps to Skill-Quality points.

Benign-vs-real heuristics (the judgment the skill must encode):
- `7600` + METAR fog + on approach to KBOS → **benign** (routine lost-comms). Bare model over-escalates.
- `rapid_descent` that is a normal approach descent into KBOS → **benign**. Bare model cries wolf.
- `going_dark` mid-cruise over open water → **concern**; `going_dark` low on approach → **benign**. The skill supplies the disambiguation.
- `7700` + erratic + steep descent, no benign explanation → **emergency** (easy case, both arms likely pass — don't lean the delta here).

## Contracts
**Flag** you READ (`workspace/flags/{icao24}-{ts}.json`):
```json
{ "icao24":"a47597","ts":1782141713,"rule":"emergency_squawk","severity":"high",
  "lat":42.36,"lon":-71.02,"evidence":{"squawk":"7700"} }
```
**Verdict** you WRITE (`workspace/verdicts/{icao24}-{ts}.json`):
```json
{ "icao24":"a47597","flag_ts":1782141713,"assessment":"benign|concern|emergency",
  "confidence":0.0,"summary":"one-line plain-language explanation",
  "enrichment":{"metar":"...","nearest_airport":"KBOS","aircraft_type":"..."} }
```
`assessment` ∈ `benign | concern | emergency`. All timestamps epoch **seconds**. Validate output through `contracts/validate.rb` before writing.

## Resilience
Wrap the main loop: on a frontier-call failure, **fall back to local** (the routing story) or write a `"could not assess"` verdict. Never crash. `--offline` covers network; this covers everything else.

## DONE when (self-test, in isolation)
- Dropping a sample flag fixture produces a **schema-valid verdict** in `workspace/verdicts/` with enrichment populated.
- `agentskills validate ./skills/flight-investigation` is **GREEN**.
- `--offline` works with no network.
- Verified with a fixture flag — the real watcher is NOT needed. Write these as actual test FILES.
