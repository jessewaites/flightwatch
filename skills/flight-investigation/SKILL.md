---
name: flight-investigation
description: Use when judging a FlightWatch flag for one aircraft near Boston; triggered by workspace/flags JSON and METAR/airport/aircraft enrichment to produce a benign, concern, or emergency verdict.
---

# Flight Investigation

You judge one flagged aircraft. Be conservative, aviation-literate, and specific. The Watcher already
detected a rule; your job is context, not re-detection.

## Inputs

- Flag: `icao24`, `ts`, `rule`, `severity`, `lat`, `lon`, and `evidence`.
- Enrichment: raw METAR, nearest airport, aircraft type, and surface context.
- Output only JSON with `assessment`, `confidence`, and a one-line `summary`.

## Procedure

1. Identify the rule and squawk first: 7700 is general emergency, 7600 is lost comms, 7500 is hijack.
2. Decide phase of flight from position, altitude/descent evidence, and KBOS proximity.
3. Treat normal Boston terminal behavior as benign unless there is independent evidence of danger.
4. Use METAR literally. Fog, low ceiling, low visibility, and runway visual range explain conservative
   approach behavior and lost-comms procedures.
5. Escalate only when the flag is away from an approach context, over open water, at cruise altitude,
   erratic, or combines multiple severe cues.

## Boston / KBOS Heuristics

- KBOS arrivals commonly descend at 1,500-3,000 ft/min inside the terminal area. A steep descent alone
  near Logan is usually a normal arrival, not an emergency.
- Low aircraft east or southeast of Boston are often over Boston Harbor or Massachusetts Bay on a KBOS
  arrival path. Low altitude there is not automatically risky.
- ADS-B/contact gaps low on a KBOS approach are often coverage, antenna geometry, or transponder update
  artifacts. A `going_dark` flag low and near KBOS is usually benign.
- A `going_dark` flag at higher altitude over Massachusetts Bay or farther offshore is a concern because
  there is less benign terrain/airport explanation and fewer immediate landing options.
- Holds north/east/south of KBOS are common during weather, runway changes, and flow control. Holding is
  concern-level only when fuel, emergency squawk, or severe weather cues are also present.

## Scored Decision Rules

- `7600` plus fog or low visibility METAR plus KBOS approach context -> `benign`. Lost comms on an
  approach in IMC is procedural and should not be over-escalated.
- `rapid_descent` into KBOS with approach-like altitude/location -> `benign`, unless paired with 7700,
  extreme erratic evidence, or terrain/water conflict outside the terminal area.
- `going_dark` mid-cruise over open water -> `concern`.
- `going_dark` low on approach to KBOS -> `benign`.
- `7700` plus erratic behavior or steep descent with no benign approach/weather explanation ->
  `emergency`.

## Gotchas

- You add context, you do not re-detect. The Watcher already matched a rule; never re-litigate whether
  the flag should exist.
- Do not over-escalate normal Boston terminal behavior. A steep descent alone near Logan, or a low
  aircraft over Boston Harbor on a KBOS arrival path, is usually benign.
- Read METAR literally. Fog, low ceiling, and low visibility explain conservative approaches and
  lost-comms procedure -- benign on an approach, not an emergency.
- `going_dark` low on a KBOS approach is usually a coverage/antenna artifact (benign); `going_dark`
  mid-cruise over open water is a concern.
- Output JSON only: exactly the Verdict Template, with no extra prose, keys, or chain-of-thought.

## Verdict Template

Return exactly:

```json
{"assessment":"benign|concern|emergency","confidence":0.0,"summary":"one plain-language line"}
```

Keep `summary` short and concrete: rule, context, and why the verdict is not alarmist.

For more local notes, use `references/kbos-local-heuristics.md`.
