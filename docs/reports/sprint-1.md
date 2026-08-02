# Sprint 1 — Detection engine

Date: 2026-08-02 · Built by Fable (Claude Code)

## What shipped

- **Debuff path (the engine's spine):** `UNIT_AURA` registered via
  `RegisterUnitEvent` filtered to `"player"`. Uses the incremental
  `updateInfo.addedAuras` payload when present; falls back to a
  whole-bar rescan (`C_UnitAuras.GetAuraDataByIndex`, HARMFUL, up to 40
  slots) on full updates or missing payloads. Every `spellId` read goes
  through `Guard()` before the `SATED_DEBUFFS` lookup.
- **Cast path (announce feed):** `UNIT_SPELLCAST_SUCCEEDED` registered
  for `"player"` **and `"pet"`** — divergence from the plan's
  player-only wording, because Primal Rage (264667, already in
  LUST_CASTS) is cast by the hunter *pet*. Sets `mine = true` on the
  window; announce.lua stays empty this sprint.
- **Window record:** `SatedDB.lastLust = { at = GetTime(), server =
  GetServerTime(), mine }`. Elapsed is always computed from the server
  timestamp so it survives /reload. Re-detections inside an active
  window (elapsed < 600s) are ignored; a cast event landing inside an
  existing window only upgrades the `mine` flag (covers both orderings
  of cast-event vs debuff-event).
- **`/sated`** now a subcommand dispatcher; bare `/sated` reports
  "last lust m:ss ago (yours)" or the no-lust-recorded line.
- Detection prints one local confirmation line: "Lust detected — timers
  armed."

## Divergences from plan

- `UNIT_SPELLCAST_SUCCEEDED` also watches unit `"pet"` (reason above).
  Flagged, reversible in one line if pet casts prove noisy.
- Slash handling restructured into a `commands` table now rather than in
  Sprint 2 — same behavior, cheaper to extend.

## Verification (machine, done)

`python tests/run_tests.py` — **17/17 pass** (5 carried + 12 new):

- Own debuff opens window, `mine=false`; debuff-only detection works
  (someone else's lust).
- Cast tags `mine=true`; the debuff arriving right after does **not**
  re-open or double-print; reverse order (debuff first, cast second)
  upgrades `mine` without resetting the window timestamp.
- Re-detections inside an active window ignored.
- Secret aura spellId and secret cast spellId both degrade silently —
  no lua error, no false window (simulated with error-on-arithmetic
  sentinel values and `issecretvalue`).
- Full-update payload triggers the rescan fallback and still detects.
- Non-lust auras/casts open nothing.
- `/sated` shows a correct mm:ss clock (1:30 at 90s), including after a
  simulated /reload restoring SavedVariables with a 90s-old server
  timestamp.

## Verification (in-game, Jess — do this, don't skip)

- [ ] On a lust-capable character (or with a friendly shaman at a
      dummy): pop lust → chat line appears, `/sated` shows a running
      clock.
- [ ] Someone ELSE pops lust → same result (debuff path, not cast path).
- [ ] /reload mid-window → `/sated` still shows correct elapsed time.

## What's deferred

- Timer marks/alerts → Sprint 2. `Sated.OnWindowOpened` seam is already
  in place for both the timer engine and announce layer.
