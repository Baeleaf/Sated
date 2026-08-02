# Sprint 2 — Timer engine + local alerts

Date: 2026-08-02 · Built by Fable (Claude Code)

## What shipped

- **Timer engine:** on window open, one `C_Timer.NewTimer` per mark in
  `SatedDB.marks or DEFAULT_MARKS` (NewTimer over the plan's
  `C_Timer.After` so pending marks are cancellable — needed by
  `/sated reset` and mark changes; flagged as a divergence-in-letter,
  not spirit). `PLAYER_ENTERING_WORLD` (login//reload/zone-in) re-arms:
  remaining = mark − elapsed-from-server-timestamp, so passed marks
  never re-fire and the handler is idempotent (cancel-then-arm).
- **Alerts:** dedicated `MessageFrame` (`SatedMessageFrame`,
  RaidNotice-style: top-center, GameFontNormalHuge, 4s visible, 1s
  fade) showing "Lust used 5:00 ago" + `PlaySound`. **Sound kit:
  `SOUNDKIT.RAID_WARNING` (8959), fallback literal if SOUNDKIT is
  absent** — as the plan asked, noted here. Pure display path: no chat,
  no comms, works in combat.
- **Slash:** `/sated marks 180 300 600` (validated, sorted, persisted,
  re-arms mid-window), `/sated sound on|off` (default on), `/sated
  reset` (cancels pending marks, clears window). All persisted to
  SatedDB; writes ride WoW's own logout flush — no per-frame writes.

## Divergences from plan

- `C_Timer.NewTimer` instead of `C_Timer.After` (cancellation; reason
  above).
- "Marks past 10:00 also clear the active window": implemented via the
  existing design rather than extra code — window activity is *computed*
  (`elapsed < 600`), so the window self-expires at 10:00 exactly, while
  `lastLust` stays recorded so `/sated` can still answer "how long ago."
  New lust after 10:00 opens a fresh window. No separate clearing step
  exists to get out of sync.

## Verification (machine, done)

`python tests/run_tests.py` — **26/26 pass** (17 carried + 9 new):

- `/sated marks 10 20 30` + lust → exactly 3 alerts at 10/20/30s with 3
  sounds, correct labels (mirrors the plan's in-game check).
- Default marks fire at 3:00/5:00/10:00.
- Simulated /reload at 15s with 10/20/30 marks → exactly the 20s and
  30s alerts fire; the 10s one does not double-fire (plan's check).
- Repeated `PLAYER_ENTERING_WORLD` (zone-in) never double-fires.
- Alerts fire while in combat (display path).
- `sound off` shows alerts silently; `on` restores; both persisted.
- `reset` clears the window, cancels pending timers, status reads "no
  lust recorded."
- Changing marks mid-window re-arms against the same window and cancels
  the old schedule.
- Invalid `marks` input rejected with usage text, nothing persisted.

## Verification (in-game, Jess — do this, don't skip)

- [ ] `/sated marks 10 20 30` then pop lust at a dummy: three alerts
      land at 10/20/30s with sound.
- [ ] /reload at ~15s: the 20s and 30s alerts still fire, the 10s one
      doesn't double-fire.
- [ ] Alerts fire while actively in combat with the dummy.
- [ ] `/sated marks 180 300 600` to restore real marks; settings
      survive a full logout.

## What's deferred

- Party announce → Sprint 3 (the `Sated.OnWindowOpened` seam carries
  the `mine` flag it needs).
