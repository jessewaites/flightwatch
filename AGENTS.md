# FlightWatch — system map (for conductor agents)

Multi-agent airspace anomaly detection over Boston. Three agents, three scopes of context, talking
ONLY through the `workspace/` file bus. Built contract-first so tracks build in parallel against frozen
shapes and converge at the end. **`CLAUDE.md` has the per-lane rules; this file is the system overview.**

## The pipeline
```
Track A (data) ── normalized frames ──▶ Watcher ── flags/ ──▶ Investigator ── verdicts/ ──┐
  OpenSky / replay                      (granite4:micro)       (frontier Claude)           │
                                                                                           ▼
                                                            Synthesizer ── situations/ ──▶ UI (Rails+Leaflet)
                                                            (frontier/mid)   watches workspace/, pushes via Action Cable
```
Delegation is the file bus: the Watcher *writing a flag file* is what triggers the Investigator. No
in-process calls, no MCP, no sub-agents, no shared framework or language.

## The three agents (identity docs in `agents/`)
| Agent | Model | Fires | Reads → Writes | Skill | Identity doc |
|---|---|---|---|---|---|
| Watcher | local `granite4:micro` (Ollama) | every tick | frames → `flags/` | flight-anomaly-rules | `agents/watcher.md` |
| Investigator | frontier (Claude) | per flag | `flags/` → `verdicts/` | flight-investigation | `agents/investigator.md` |
| Synthesizer | frontier/mid | per window | `flags/`+`verdicts/` → `situations/` | airspace-situation | `agents/synthesizer.md` |

Detection is deterministic CODE (`detect.rb`); judgment is the MODEL. The Watcher's only AI job is
triage prioritization when several planes flag at once.

## Layout
- `contracts/` — FROZEN schemas + `validate.rb` + fixtures. The seam everything targets. Do not edit after freeze.
- `agents/` — `watcher.rb` / `investigator.rb` / `synthesizer.rb` + their `*.md` identity docs.
- `skills/` — the 3 validated skills (`agentskills validate ./skills/<name>`).
- `data/` (Track A) · `enrichment/` (Track C) · `evals/` (Track E) · `ui/` (Track D).
- `workspace/` — runtime file bus: `flags/ verdicts/ situations/ control/ tracks/ observe/` (contents gitignored).
- `briefs/` — paste-ready kickoff prompt per track.

## Stack (do not relitigate)
Ruby + RubyLLM. NOT Python/LangChain. No database (state = `workspace/` JSON + in-memory buffer).
Validator command is `agentskills`, NOT `skills-ref`. Watcher → Ollama `http://localhost:11434/v1`;
Investigator/Synthesizer → Anthropic API.

## Running the system (Phase 2)
Separate processes sharing one `workspace/`: one per agent + the Rails server, plus `ollama serve`.
A `Procfile` (foreman/overmind) boots them together. Two flags: `--no-skill` (scored on the
Investigator) and `--offline` (replay + cached fixtures, the demo's safe path).
