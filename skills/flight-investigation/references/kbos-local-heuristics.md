# KBOS Local Heuristics

Use these notes to disambiguate Boston-area flags.

## Approach Context

Consider an aircraft "on approach to KBOS" when it is within roughly 18 nm of KBOS, below about
7,000 ft if altitude is available, moving through the Boston terminal area, or the surface context says
KBOS approach/arrival corridor. Missing altitude does not defeat approach context if the flag is low and
close to Logan.

Boston Logan sits on the harbor. Approaches and departures routinely cross water and dense urban
airspace at low altitude. Do not treat "low over water near Boston" as an emergency by itself.

## METAR Cues

METAR strings with `FG`, `BR`, `OVC00`, `BKN00`, `1/2SM`, `1/4SM`, or `R..../` indicate instrument
conditions or runway visual range constraints. In that context, lost-comms and conservative descent
profiles should be treated as procedural unless another emergency cue is present.

## Rule Matrix

- emergency_squawk with squawk 7700: emergency unless the evidence is obviously stale or contradictory.
- emergency_squawk with squawk 7600: benign on KBOS approach in IMC; concern otherwise.
- rapid_descent: benign inside KBOS approach context at ordinary arrival rates; concern away from the
  airport; emergency only with 7700, erratic heading/speed, or extreme descent.
- going_dark: benign low/near KBOS, concern over Massachusetts Bay at cruise altitude or farther from
  the field, emergency only with an emergency squawk or other severe cue.
- holding_pattern: benign/concern around KBOS depending on weather and duration; not emergency alone.
