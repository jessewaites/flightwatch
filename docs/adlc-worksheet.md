# FlightWatch ADLC Worksheet

Event: The Open Accelerator Agent Build Day, Lane 3  
Project: FlightWatch, multi-agent airspace anomaly detection over Boston  
Last updated: 2026-06-27 13:06 EDT

## Scope

Build a shippable Lane 3 prototype with at least two cooperating agents and at least two custom skills. FlightWatch uses three agents:

- Watcher: scans normalized Boston air traffic frames and writes anomaly flags.
- Investigator: reads flags and writes verdicts.
- Synthesizer: reads flags plus verdicts and writes named airspace situations.

Agents cooperate only through the `workspace/` file bus. The demo runs from a planted offline replay so the final presentation does not depend on live traffic or external APIs.

## Design

The system is contract-first. `contracts/` defines frozen JSON shapes for frames, flags, verdicts, and situations. Each agent owns one transformation and communicates by writing files:

- `workspace/tracks/` to Watcher.
- `workspace/flags/` to Investigator.
- `workspace/verdicts/` to Synthesizer and UI.
- `workspace/situations/` to UI.
- `workspace/observe/run.jsonl` for run evidence and routing metrics.

Detection is deterministic code in `skills/flight-anomaly-rules/scripts/detect.rb`; model judgment starts after a candidate flag exists. This keeps high-volume scanning cheap and makes the model-selection boundary easy to explain.

## Build

Implemented components:

- Data replay and normalized frame production in `data/` and `bin/produce_frames.rb`.
- Watcher, Investigator, and Synthesizer agents in `agents/`.
- Three custom skills in `skills/`: `flight-anomaly-rules`, `flight-investigation`, and `airspace-situation`.
- Offline planted scenario and eval gates in `evals/`.
- Rails plus Leaflet dashboard in `ui/`.
- End-to-end process wiring through `bin/pipeline` and `Procfile`.

## Evaluate

Current required eval command:

```sh
ruby evals/run_all.rb
```

Latest result:

- Overall: PASS.
- Detector Gate A: PASS, 4/4 cases.
- Investigator Gate B: PASS.
- With skill: 5/5, accuracy 1.0.
- Without skill median: 2/5, accuracy 0.4.
- Skill-quality delta: +0.6 accuracy.

Artifacts:

- `evals/evals.json`
- `evals/detector_results.json`
- `benchmark.json`
- `data/flightwatch-boston-planted-2026-06-22.jsonl`

One eval harness correction was made during the run: the holding-pattern fixture now includes enough samples to satisfy the detector's 80-second minimum window while preserving the heading-wraparound case.

## Deploy

Demo path:

```sh
cd ui && bundle install && bin/dev
bin/pipeline
```

The dashboard reads `../workspace`. `bin/pipeline` runs the frame producer, Watcher, Investigator, and Synthesizer against the same file bus. Demo mode uses the planted replay; online mode requires OpenSky credentials and `ANTHROPIC_API_KEY`.

Operational fallback:

- Watcher uses local Ollama when available and deterministic triage if the model is unavailable.
- Investigator and Synthesizer support `--offline` fixture-backed runs so the demo does not depend on network calls.

## Observe

Every agent appends action evidence to `workspace/observe/run.jsonl`. This supports:

- Routing table evidence: agent, model, route, latency, tokens, and cost when available.
- Detection precision observation: compare Watcher flags with Investigator verdicts and track the benign rate.
- Degradation evidence: skipped malformed inputs or local fallback events, if they occur.

The evaluate-to-observe loop is: `evals/run_all.rb` proves the skill delta before the demo; `workspace/observe/run.jsonl` and `workspace/verdicts/` show runtime behavior; benign verdict rates identify rules to tighten.

## Iterate

Next improvements after the demo:

- Tune holding-pattern thresholds using observed benign-rate feedback.
- Add a historical baseline for traffic-volume anomalies, not just rule-coded anomalies.
- Replace JSONL-only observability with OpenTelemetry plus Phoenix or Langfuse if the project moves beyond build-day scope.
- Expand Investigator eval cases beyond the current fixture set and include real model runs when budget and network reliability allow.

