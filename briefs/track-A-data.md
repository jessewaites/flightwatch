# Track A — Data · owns `data/`

> Paste this whole file as the opening prompt in the Track A worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane — you should not need the 81KB spec.

## Lane rules (non-negotiable)
- Work **only** in `data/`. Never touch another track's dir or `contracts/` (frozen).
- Build against `contracts/fixtures` + the captured JSONL, **not** against other tracks (they don't exist in your worktree).
- Ruby (no Python/LangChain). **No database.** Agents talk only through the `workspace/` file bus.
- If a frozen contract seems wrong: **STOP and flag it** — never edit `contracts/` silently.
- You are DONE when your self-test passes in isolation.

## What you build
The data layer in `data/`:
1. **OpenSky OAuth2 token manager** (Ruby, Net::HTTP or Faraday — NOT the Python binding). Read `client_id`/`client_secret` from `.env` / `credentials.json`, POST to the token endpoint, cache the bearer token, **auto-refresh before the 30-min expiry**. `credentials.json` and `.env` stay gitignored.
   - Token endpoint: `https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token`
2. **Poller**: `GET /states/all` on the Boston bbox every 5–10s. Stay on the laptop's IP (cloud IPs are blocked).
   - Boston bbox: `lamin=42.2 lomin=-71.2 lamax=42.5 lomax=-70.9`
3. **Normalizer**: decode the array-of-arrays into the frozen `frame` contract using the field-index map below. **Convert metric → ft / ft·min⁻¹ at normalization** (do it once, here).
4. **Rolling buffer**: in-memory, keyed by `icao24`, holding each plane's last ~**60 frames** of positions (~5–10 min). **Evict a plane ~5 min after its last contact.** Must return a correct recent-track for a queried `icao24` (holding-pattern + going-dark depend on this).
5. **Replay harness**: read `data/flightwatch-boston-raw-2026-06-22.jsonl` and emit frames in sequence as if live.
6. **Frame-source toggle**: each tick, read `workspace/control/mode.json` (`{"source":"realtime"}` or `{"source":"demo"}`) and pull from the live poll or the replay file accordingly. Downstream never knows the source changed — it just receives frames. No process restart.

## Contracts you target
**Normalized frame** (one tick; you EMIT this shape):
```json
{ "ts": 1782141713,
  "aircraft": [
    { "icao24": "a47597", "callsign": "DAL1398", "lat": 42.3628, "lon": -71.0213,
      "baro_alt_ft": null, "velocity_kt": 0, "heading": 253.12, "vert_rate_fpm": null,
      "on_ground": true, "squawk": null, "last_contact": 1782141657 } ] }
```
**ALL timestamps are epoch SECONDS (integer)** — `ts`, `last_contact`, everything. Never milliseconds.

**OpenSky `/states/all` field-index map (AUTHORITATIVE — do NOT read from memory):**
```
0 icao24  1 callsign  2 origin_country  3 time_position  4 last_contact   <-- going-dark uses 4
5 longitude  6 latitude  7 baro_altitude(METERS)  8 on_ground   <-- filter these out
9 velocity(m/s)  10 true_track(heading)  11 vertical_rate(M/S, +climb)   <-- descent uses 11
12 sensors  13 geo_altitude(METERS)  14 squawk   <-- 7500/7600/7700 LIVE HERE (NOT 15)
15 spi(bool)  16 position_source  17 category
```

## Gotchas (these caused real bugs)
- **Squawk is index 14, NOT 15.** 15 is the `spi` boolean.
- **Units are METRIC.** `vertical_rate`=m/s, altitudes=meters. Convert to ft / ft·min⁻¹ once, here.
- **Filter on-ground.** Parked/taxiing at Logan come back `on_ground=true`, velocity~0, null alt. Pass `on_ground` through faithfully so B can filter.
- **Going-dark is staleness, not a vanishing row.** OpenSky keeps emitting ~300s after last contact. The signal is a growing gap between frame `ts` and the plane's `last_contact` — preserve `last_contact` accurately in every frame.
- Anonymous access works but is rate-limited harder; the authenticated client gives headroom.

## DONE when (your self-test, in isolation)
- Normalizer run on the raw capture emits frames that **validate against the `frame` schema** (`contracts/validate.rb`).
- Buffer returns a correct recent-track for a queried `icao24`.
- Replay harness plays the raw file frame-by-frame.
- Write these as actual test FILES in `data/`, not by-hand checks.

> Prerequisite: `data/flightwatch-boston-raw-2026-06-22.jsonl` must be present. If it's missing, stop and ask — you can't build or test without it.
