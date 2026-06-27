---
name: flight-anomaly-rules
description: Use when scanning normalized FlightWatch aircraft frames for deterministic airspace anomalies, emergency squawks, rapid descents, stale contacts, holding patterns, altitude outliers, or Watcher flag evidence.
---

# Flight Anomaly Rules

## Purpose

This skill documents the deterministic Watcher detection rules for Boston FlightWatch. Detection is code, not model judgment. The callable script is bundled at `scripts/detect.rb` and exposes the frozen signature:

```ruby
detect(frame, buffer) -> [flag]
```

Use it when a normalized frame arrives from Track A and the Watcher needs rule-based flag candidates before model triage.

## Input Contract

`frame` is a Hash with:

- `ts`: epoch seconds
- `aircraft`: array of normalized aircraft Hashes

Each aircraft has named normalized fields: `icao24`, `callsign`, `lat`, `lon`, `baro_alt_ft`, `velocity_kt`, `heading`, `vert_rate_fpm`, `on_ground`, `squawk`, `last_contact`.

`buffer` is recent prior frames in the same normalized shape. The detector uses it for going-dark history and holding-pattern geometry.

## Global Gotchas

- Filter `on_ground == true` before every rule. Parked or taxiing aircraft must never flag.
- Squawk is OpenSky raw index 14 before normalization. Index 15 is `spi`, not squawk.
- Track A normalizes units. The detector reads `vert_rate_fpm`, `baro_alt_ft`, and `velocity_kt`; do not apply metric conversions here.
- All timestamps are epoch seconds.
- Skip malformed aircraft and keep scanning the frame.
- Emit at most one flag per aircraft per tick because the file-bus path is `workspace/flags/{icao24}-{ts}.json`.

## Rule Order

Rules run in this order. The first matching rule wins for that aircraft:

1. `emergency_squawk`
2. `rapid_descent`
3. `going_dark`
4. `holding_pattern`
5. `altitude_outlier`

## Rules

### emergency_squawk

Pure field read from normalized `squawk`.

- `7700`: general emergency
- `7500`: hijack
- `7600`: radio failure
- severity: `high`

### rapid_descent

Flag if `vert_rate_fpm < -2360`, approximately the normalized equivalent of below -12 m/s.

- severity: `high`
- evidence: `vert_rate_fpm`, `threshold_fpm`

### going_dark

Flag a growing stale-contact gap between frame `ts` and aircraft `last_contact`.

- current gap threshold: `>= 180s`
- with history: current gap must be at least `30s` larger than prior max gap
- without history: current gap must be `>= 300s`
- severity: `medium`, or `high` once gap reaches `300s`
- evidence: `gap_s`, `last_contact`

### holding_pattern

Detect "turns a lot but stays put" using buffered geometry.

Starting algorithm:

- use same-aircraft samples in the last `120s`
- require at least `80s` of window
- accumulate signed heading deltas with wraparound handling, so `359 -> 1` is a `+2` degree turn
- flag when the dominant turn direction accumulates at least `270 degrees`
- require opposite-direction turn no more than `60 degrees`
- require all samples remain within about `3 nm` radius
- severity: `medium`
- evidence: `cumulative_turn_deg`, `window_s`, `radius_nm`, `direction`

This rule is intentionally conservative: a course change without tight radius should not flag.

### altitude_outlier

Stretch rule. Compare airborne peers in the same frame.

- require at least four airborne peer altitudes
- flag if altitude differs from peer median by at least `6000 ft`
- severity: `low`, or `medium` above `10000 ft` delta
- evidence: `baro_alt_ft`, `peer_median_ft`, `delta_ft`

## Flag Output Template

```json
{
  "icao24": "a47597",
  "ts": 1782141713,
  "rule": "emergency_squawk",
  "severity": "high",
  "lat": 42.36,
  "lon": -71.02,
  "evidence": { "squawk": "7700" }
}
```

Valid `rule` values are `emergency_squawk`, `rapid_descent`, `going_dark`, `holding_pattern`, and `altitude_outlier`.

Valid `severity` values are `low`, `medium`, and `high`.

Validate flags through `contracts/validate.rb` before writing to the file bus.
