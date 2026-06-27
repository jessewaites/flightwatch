# Track D — UI · owns `ui/` (stripped Rails + Action Cable + Leaflet + Tailwind)

> Paste this whole file as the opening prompt in the Track D worktree.
> `CLAUDE.md` (auto-loaded) has the shared invariants. This brief is your lane.
> KEY UNLOCK: you need ZERO real agents. Build entirely against the `contracts/fixtures` sample workspace.

## Lane rules (non-negotiable)
- Work **only** in `ui/`. Never touch another track's dir or `contracts/` (frozen).
- Build against the `contracts/fixtures` sample workspace. Render from `workspace/` JSON.
- **No database, no ActiveRecord, no models.** If you reach for `rails generate model`, STOP.
- Agents ↔ UI communicate ONLY through the `workspace/` file bus — never HTTP between processes.
- You are DONE when your self-test passes in isolation.

## Build command (resolved)
`rails new ui --skip-active-record` — **standard Rails, NOT `--minimal`.** Standard Rails ships Action Cable + Hotwire/Turbo by default (the map channel and the tab feeds need them). `--skip-active-record` keeps the no-DB design. Confirm `turbo-rails` is present after scaffold (it is, by default).

Structure — build exactly this, nothing more:
- **`DashboardController#index`** — the single page. Route: `root "dashboard#index"`. No other controllers/models.

## The file bus (both directions go through `workspace/`)
- **Agents → UI (display):** Rails watches `workspace/` with the **`listen` gem**. A new flag/verdict/situation file fires an **`AirspaceChannel`** (Action Cable) broadcast the index subscribes to → drives marker updates + camera choreography. Agents just write files; Rails is a reader that pushes.
- **UI → agents (toggle):** the UI WRITES `workspace/control/mode.json` (`{"source":"realtime"}` or `{"source":"demo"}`). Track A's producer reads it each tick. No restart, no HTTP.

## Tabbed layout: Map · Anomalies · Synthesis (one page, one controller, no models)
A tab strip switches the MAIN region between three panels. Tabs named for the USER concept, each maps to an agent's output.
- **Tab 1 — Map (default, active on load):** Leaflet + OSM tiles, full-bleed. The demo stage; all choreography lives here.
- **Tab 2 — Anomalies (the Investigator's surface):** investigated anomalies. Each row pairs the WHY (Watcher's flag: rule + severity + evidence) with the Investigator's verdict (assessment, confidence, summary, enrichment).
- **Tab 3 — Synthesis (Synthesizer report):** each situation file appends/updates the report. If the Synthesizer is cut, show a clean empty state (don't imply it's mandatory).

**Anomalies feed (flag first, verdict fills in, ONE row):** when a flag lands → `Turbo::StreamsChannel.broadcast_append_to "anomalies", target:"anomaly-feed", ...`, dom_id keyed `{icao24}-{flag_ts}`, shows pending state. When the matching verdict lands → `broadcast_replace_to` on the same dom_id, filling assessment + summary. Same pattern: situations → `"synthesis"`. The view uses `turbo_stream_from "anomalies"` / `"synthesis"`. The class methods work with NO ActiveRecord. One `listen` file event drives BOTH the map marker AND the tab feed. Newest-on-top (or append + auto-scroll). Clean empty states.

**Persistent chrome, NOT tabs** (stay visible across all tabs):
- **Routing-table panel** (docked): live per-agent table — agent · model · route · tokens · $ · latency · TOTAL. Watcher row ≈ $0; investigator/synthesizer show real cost but fire rarely. This is the model-selection evidence, on screen.
- **Situation banner** (full-width, TOP): drops in when a situation file lands. The demo CLIMAX — unmissable, persistent once fired, entrance pulse. NOT a tab.

## CRITICAL Leaflet gotchas
- **Do NOT unmount the map on tab switch.** All three panels stay in the DOM; switch by toggling a visibility class, never destroy/recreate the Map panel (a rebuilt Leaflet loses camera state + breaks choreography).
- **On every return to the Map tab, call `map.invalidateSize()`** — a Leaflet map sized while `display:none` renders grey/half-tiled until this runs. This is the single most likely tab bug.

## Map visuals
- **Plane icon:** inline SVG in a Leaflet `divIcon` (not a PNG). North-pointing top-down airplane, single `<path>`, fill driven by CSS class. (Asset: `airplane-svgrepo-com.svg` — nose up = heading 0 = north.)
- **Rotation = `true_track`** via CSS `transform: rotate(Ndeg)`, raw heading, NO offset. This makes it read as live air traffic — free, high value.
- **Color encodes STATE, not identity** (do NOT color per plane): normal → one calm neutral base; **flagged → red** (the eye-snap, only works if normal planes are neutral); under investigation (focus) → distinct highlight (amber/cyan); on-ground → muted/desaturated (never flagged). Recolor the single path's fill per state.
- **Airport marker:** static KBOS (Logan) marker so "ground stop at KBOS" is legible.
- **Callsign labels:** only on the flagged/focus plane (all = text soup).

## Camera choreography (the investigation zoom)
On flag broadcast → `map.flyTo([lat,lon], CLOSE_ZOOM)`; on verdict → `map.flyTo(OVERVIEW_CENTER, OVERVIEW_ZOOM)`. Makes the handoff visible. Polish (sheddable, after the gate): dim other markers, pulse ring on focus, anchored verdict popup with a hold, focus-plane polyline. If the Investigator runs fast, add ~1–2s dwell so the zoom registers. UI-only.

## Demo narrative to build for (the cold open)
OPEN on **real-time** ("traffic over Boston right now") → toggle to **demo mode** and run the scripted scenario. Make real-time robust: (1) pre-warm — already polling, planes on screen at t=0; (2) auto-fallback — on a failed/empty poll, hold the most recent good frame instead of going blank. The scripted demo runs on the Map tab (flyTo only reads while Map is visible).

## Styling
**Tailwind** via `tailwindcss-rails`, **class-based dark mode** (`darkMode: 'class'`) with a toggle button (NOT OS-auto). Dark-mode gotcha: OSM default tiles are light — swap in a **dark tile layer (CartoDB dark_all)** on the same toggle, or you get dark chrome around a bright map.

## Contracts you READ from the fixture workspace
- `flags/{icao24}-{ts}.json` — `{icao24, ts, rule, severity, lat, lon, evidence}`
- `verdicts/{icao24}-{ts}.json` — `{icao24, flag_ts, assessment, confidence, summary, enrichment}`
- `situations/{id}.json` — `{id, ts, kind, airport, icao24s, summary}`
All timestamps epoch **seconds**.

## DONE when (self-test against fixtures, ZERO real agents)
- Map renders planes at correct positions; a fixture flag reds a plane and flies the camera in; a fixture verdict pops and flies out; a fixture situation drops the top banner; the routing-table panel shows rows.
- The **Anomalies tab appends a fixture flag row, then fills it in place when the matching fixture verdict lands**; the **Synthesis tab renders fixture situations**.
- **Switching tabs does not unmount the map** (and returning to Map calls `invalidateSize`).
- Dark mode + the demo/real-time toggle work.
