# FlightWatch Model-Selection Rationale

FlightWatch routes work by cost, latency, and judgment depth. High-volume scanning stays local and deterministic; expensive frontier reasoning runs only after the system has evidence worth investigating.

| Agent | Model route | Frequency | Why this model |
|---|---|---:|---|
| Watcher | local `granite4:micro` via Ollama, with deterministic fallback | every frame | Constant scanning needs low latency and near-zero marginal cost. The detector is code; the local model only prioritizes multiple simultaneous flags. |
| Investigator | frontier Claude via Anthropic, offline fixture fallback | per flag | This is the highest-value judgment step. It needs aviation context to distinguish benign approach behavior from real concern, and it fires only on anomalies. |
| Synthesizer | frontier or mid model, offline fixture fallback | per window | It names multi-plane situations that no single flag can explain. It runs rarely, after flags and verdicts already exist. |

## Cost And Latency Argument

The cascade keeps cost proportional to anomalies, not traffic volume:

- Every aircraft in every frame is checked by deterministic Ruby rules.
- The local Watcher model is optional triage, not detection.
- The Investigator runs only when a flag file exists.
- The Synthesizer runs only when a multi-plane window needs a situation label.

This architecture is cheaper and more reliable than sending every aircraft state to a frontier model. It also gives a clear privacy story: most raw traffic data stays local, and only narrow anomaly context needs frontier reasoning.

## Quantitative Evidence

Latest eval command:

```sh
ruby evals/run_all.rb
```

Latest benchmark:

- Detector Gate A: PASS, 4/4 deterministic rule cases.
- Investigator with `flight-investigation` skill: 5/5, accuracy 1.0.
- Investigator without skill, median of 3 runs: 2/5, accuracy 0.4.
- Skill-quality delta: +0.6 accuracy.

The scored artifact is the Investigator's `flight-investigation` skill. The detector gate proves `detect.rb` works; it is not the scored with-skill delta.

## Routing Receipt

During runtime, agents append events to `workspace/observe/run.jsonl`. The dashboard and process logs use those events as the routing receipt:

| Agent | Expected route | Expected cost behavior |
|---|---|---|
| Watcher | `local/cheap` or deterministic fallback | approximately zero per tick |
| Investigator | `frontier/strong` or `frontier->local fallback (offline)` | bounded by flag count |
| Synthesizer | `frontier-or-mid/summary` or offline fallback | bounded by situation windows |

The route table is intentionally part of the product surface because it proves the model-selection rationale during the demo rather than leaving it as a separate claim.

