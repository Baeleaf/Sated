# Sprint 7 — Marks anchored to the debuff falling off

Date: 2026-08-02 · Built by Fable (Claude Code) · Jess's clarification
of the Sprint 6 semantics.

## The corrected model

The 10-minute Sated debuff is the blocker. What matters is **when it
falls off** (lust can be pressed again) and **how long it's been off**.
Final timeline (T = lust used):

| Moment | On-screen (+sound) | Party chat |
| --- | --- | --- |
| T | "Lust detected — timers armed" | "Lust used — back around HH:MM." |
| T+10:00 — debuff drops | **"Lust is up!"** | "Lust is up." |
| T+13:00 | "Lust has been up for 3 min" | "Lust has been up for 3 min." |
| T+15:00 / T+20:00 | same at 5 / 10 min | same |

`/sated marks` = seconds **after the debuff falls off** (default
180/300/600).

## What changed vs Sprint 6

- Mark timers re-anchored: scheduled at `ready + mark` instead of
  `use + mark`; countdown-style "Lust back in X" marks removed (the
  cast announce already carries the back-around time, and `/sated`
  shows the live countdown on demand).
- Settings schema → v3: wipes any saved marks from the older semantics
  on first load (announce mode survives — its meaning didn't change).
- README/config comments updated to the corrected model.

This is the third pass over mark semantics; the moving parts (timer
anchor, alert text, chat phrasing) are all single-site changes, which
is what kept this a small diff.

## Verification (machine, done)

`python tests/run_tests.py` — **52/52 pass**, suite re-timed:

- Exact beats asserted on-screen and in chat: "Lust is up." at T+10:00,
  "Lust has been up for 3 min. / 5 min. / 10 min." at T+13/15/20:00 —
  for own casts and for partner-cast lust (mode all).
- Custom marks (10/20/30s) fire at ready+10/20/30s.
- /reload mid-cooldown re-arms ready + marks exactly once; /reload
  after ready refires nothing already passed.
- Ready queued mid-combat flushes re-phrased ("Lust has been up for
  2:10."); ready + first mark in one fight flush as one message.
- v3 migration wipes stale marks, preserves announce mode.
- All carried guarantees: secret-value degradation, exactly-once per
  beat, solo silence, zone-change/reset queue drops, debug trail,
  ring-buffer cap.

## Verification (in-game, Jess)

Deployed — `/reload` to pick it up; old marks self-clean via migration.

- [ ] Pop lust while grouped: chat at the cast, then nothing until
      10:00 → "Lust is up." (+ on-screen/sound), then up-for reminders
      at 13:00 / 15:00 / 20:00.
- [ ] `/sated` before 10:00 shows "back up in X (around HH:MM)"; after
      shows "lust is UP — has been up for X".
- [ ] Quick version: `/sated marks 10 20` → reminders 10s and 20s
      after the "Lust is up!" moment (restore with
      `/sated marks 180 300 600`).
