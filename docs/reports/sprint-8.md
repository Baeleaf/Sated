# Sprint 8 — Artificial resets (Proving Grounds)

Date: 2026-08-02 · Built by Fable (Claude Code) · Feature request from
Jess: work correctly when lust is artificially reset (garrison Proving
Grounds).

## What changed

Previously "Lust is up" was pure wall-clock: use + 10:00. Now the
anchor is **the Sated debuff actually leaving your bar**:

- While a window is active, `UNIT_AURA` removal events (and full
  updates) trigger a bar re-check; if the debuff is gone — naturally at
  10:00 or wiped at 0:40 by a Proving Grounds reset — that moment
  becomes "Lust is up!", and the 3/5/10-min up-for marks re-anchor to
  it (on-screen and chat).
- A re-lust after a reset opens a fresh cycle: new detection, new
  ready timer, stale marks cancelled.
- `PLAYER_ENTERING_WORLD` re-syncs: if SavedVariables claim the debuff
  should still be on us but the bar disagrees after a loading screen or
  /reload, it's treated as dropped right then.
- The clock (use + 10:00) remains as fallback: it still fires ready if
  no removal was ever observed, and windows opened by the cast event
  alone (debuff never seen — e.g. fully-secret aura data) never
  interpret "absent from bar" as a drop, so secret-heavy content can't
  cause a false early "Lust is up".
- Robustness choices: drop detection is scan-based (presence check via
  guarded spellIds) rather than aura-instance-ID matching, so secret
  removal IDs degrade to a rescan instead of a miss; ready fires
  exactly once per window (`readyFired`) no matter which path gets
  there first; the ready moment (`readyServer`) persists, so up-for
  numbers stay correct across /reload.

Record shape gained `debuffSeen`, `readyServer`, `readyFired` — old
records simply fall back to clock behavior; no migration needed
(schema stays v3).

## Verification (machine, done)

`python tests/run_tests.py` — **62/62 pass** (52 carried + 10 new):

- Removal at 1:00 → "Lust is up!" immediately; status flips; marks
  land at drop+N; chat gets "Lust is up." and re-anchored "Lust has
  been up for 3 min."
- Natural expiry + trailing removal event → ready exactly once;
  removal a hair before the clock → once, stale clock timer cancelled.
- Secret removal IDs → detected via rescan.
- Unrelated debuff removals don't end the window.
- Re-lust after reset → fresh full cycle, old marks cancelled.
- Reload into a reset state → ready fires on PLAYER_ENTERING_WORLD,
  marks anchored to the resync.
- Cast-only windows trust the clock, never absence.
- All 52 carried tests unchanged and green.

## Verification (in-game, Jess)

Deployed — `/reload` to pick it up.

- [ ] Garrison Proving Grounds: pop lust, start/reset a trial so the
      Sated debuff is wiped → "Lust is up!" the moment it disappears,
      then "has been up for 3/5/10 min" from that moment.
- [ ] Re-lust right after the reset → fresh "Lust detected" and a new
      cycle.
- [ ] Normal dungeon flow unchanged: ready at 10:00, reminders after.
