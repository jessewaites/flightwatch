# contracts/ — FROZEN (Phase 0)

These are the only things the parallel tracks share. **Frozen after Phase 0.** A schema change is a
STOP-and-renegotiate event for the whole team, never a silent edit — a silent change is exactly what
breaks the merge. `validate.rb` is the executable source of truth; this file documents the same shapes.

- **`validate.rb`** — pure-Ruby validator (no gems). Every agent runs its output through it before
  writing to `workspace/`. Run `ruby contracts/validate.rb` to check all fixtures against the schemas.
- **`fixtures/`** — one sample per contract + a tiny sample `workspace/` (the thing Tracks D and E
  build against, so they need zero real agents).

## Global invariants
- **ALL timestamps are epoch SECONDS (integer), never milliseconds** — `ts`, `last_contact`, `flag_ts`.
  Going-dark computes `frame.ts - aircraft.last_contact` in seconds; one ms value breaks it silently.
- **Boston bbox:** `lamin=42.2 lomin=-71.2 lamax=42.5 lomax=-70.9`.
- **Units are normalized at the frame boundary (Track A):** altitudes in **feet**, vertical rate in
  **ft/min**, velocity in **knots**. OpenSky's raw metric values never travel past normalization.
- **Detection signature (frozen):** `detect(frame, buffer) -> [flag]` — pure deterministic code
  (`skills/flight-anomaly-rules/scripts/detect.rb`). The model does prioritization, not detection.

## OpenSky `/states/all` field-index map (AUTHORITATIVE — do not read from memory)
The raw capture is `{ "time": <epoch_s>, "states": [ [ ...18 fields... ], ... ] }`.
```
0 icao24        5 longitude          10 true_track (heading)   15 spi (bool, NOT squawk)
1 callsign      6 latitude           11 vertical_rate (M/S)     16 position_source
2 origin_country 7 baro_altitude(M)  12 sensors                17 category
3 time_position 8 on_ground (filter) 13 geo_altitude (M)
4 last_contact  9 velocity (m/s)     14 squawk  <-- 7500/7600/7700 LIVE HERE (NOT 15)
```
Burned-in: **squawk is 14, not 15** (15 is `spi`); **vertical_rate (11) + altitudes (7,13) are METRIC**;
**filter `on_ground=true`**; **going-dark = growing gap on `last_contact` (4)**, not a vanishing row.

## The four contracts

### frame — Track A emits (one polling tick, decoded into named fields)
`ts` int · `aircraft` array of:
`icao24` str · `callsign` str? · `lat` num? · `lon` num? · `baro_alt_ft` num? · `velocity_kt` num? ·
`heading` num? · `vert_rate_fpm` num? · `on_ground` bool · `squawk` str? · `last_contact` int
( `?` = nullable. ) → `fixtures/frame.sample.json`

### flag — Watcher writes to `workspace/flags/{icao24}-{ts}.json`
`icao24` str · `ts` int · `rule` enum · `severity` enum · `lat` num · `lon` num · `evidence` hash
- `rule` ∈ `emergency_squawk | rapid_descent | going_dark | holding_pattern | altitude_outlier`
- `severity` ∈ `low | medium | high`
→ `fixtures/flag.sample.json`

### verdict — Investigator writes to `workspace/verdicts/{icao24}-{ts}.json`
`icao24` str · `flag_ts` int · `assessment` enum · `confidence` num (0.0–1.0) · `summary` str ·
`enrichment` hash
- `assessment` ∈ `benign | concern | emergency`
→ `fixtures/verdict.sample.json`

### situation — Synthesizer writes to `workspace/situations/{id}.json`
`id` str · `ts` int · `kind` enum · `airport` str · `icao24s` array<str> · `summary` str
- `kind` ∈ `ground_stop | weather_diversion | runway_closure`
→ `fixtures/situation.sample.json`

## File-bus paths (the runtime delegation bus, gitignored at runtime)
```
workspace/flags/{icao24}-{ts}.json        Watcher  -> Investigator
workspace/verdicts/{icao24}-{ts}.json     Investigator -> Synthesizer + UI
workspace/situations/{id}.json            Synthesizer -> UI
workspace/control/mode.json               UI -> Track A   {"source":"realtime"|"demo"}
workspace/observe/run.jsonl               every agent appends one line per action
```
