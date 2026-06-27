# FlightWatch eval lane

Track E owns the eval gate. It stays contract-facing: no database, no cross-lane source edits, and no
network dependency.

Run everything:

```sh
ruby evals/run_all.rb
```

Outputs:

- `data/flightwatch-boston-planted-2026-06-22.jsonl` from `evals/scenario.json`
- `evals/detector_results.json` for Gate A
- `evals/evals.json` for the scored Investigator skill-quality cases
- `benchmark.json` at repo root with the with-skill vs `--no-skill` aggregate and delta

By default the detector gate uses `skills/flight-anomaly-rules/scripts/detect.rb` when it exists and a
local reference detector otherwise. Force the integrated detector with:

```sh
DETECT_IMPL=repo ruby evals/run_detector_gate.rb
```

The Investigator gate is fixture-based and deterministic so it can run before Track C's model harness is
merged. The scored mechanism is still the required one: identical flag fixtures, expected verdicts, and
only the skill-aware judgment arm differs from the no-skill baseline.
