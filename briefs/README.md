# Conductor track briefs

Paste-ready kickoff prompts, one per parallel track. Each is self-contained — an agent shouldn't need the 81KB `flightwatch-build-spec-final.md`. Shared invariants live in the repo-root `CLAUDE.md` (auto-loaded in every worktree); each brief covers only its own lane.

| Brief | Owns | Build against | Notes |
|---|---|---|---|
| [track-A-data.md](track-A-data.md) | `data/` | live OpenSky + captured JSONL | needs the raw capture in `data/` |
| [track-B-watcher.md](track-B-watcher.md) | `skills/flight-anomaly-rules/`, `agents/watcher.rb` | synthetic frames + sample flags | |
| [track-C-investigator.md](track-C-investigator.md) | `skills/flight-investigation/`, `agents/investigator.rb`, `enrichment/` | sample flags | ★ owns the scored eval delta |
| [track-D-ui.md](track-D-ui.md) | `ui/` | fixture workspace | zero real agents needed |
| [track-E-eval.md](track-E-eval.md) | `evals/` | `detect` signature + fixtures | ★ owns the eval gate |
| [track-F-synthesizer.md](track-F-synthesizer.md) | `agents/synthesizer.rb`, `skills/airspace-situation/` | flag + verdict fixtures | BUILD LAST |

## Order
1. **Phase 0 (NOT a track, do first, not parallel):** lock `contracts/` (schemas + fixtures + field-index map + bbox + `detect` signature + `validate.rb`), then FREEZE. Every brief depends on this existing.
2. **Fan out A–E** against the frozen contracts.
3. **Gate (B+C+E converge first):** Gate A detector tests green + Gate B Investigator skill delta real. No polish before this.
4. **Converge:** A→B→C spine runs (2-agent system = complete entry), then D renders.
5. **F (Synthesizer) last** — the third agent + climax banner.

All briefs share three rules: stay in your dir (never touch another's or `contracts/`); build against `contracts/fixtures`, not other tracks; you're DONE when your self-test passes in isolation.
