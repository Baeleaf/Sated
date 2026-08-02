# Sprint 5 — Off-cooldown semantics rework

Date: 2026-08-02 · Built by Fable (Claude Code) · Requested by Jess
after first in-game contact with the Sprint 0–4 build.

## What changed and why

The original marks counted **up from lust use** ("Lust used 0:10 ago").
Jess wants the addon oriented around **lust coming back off cooldown**:
know the moment it's ready, how long it's been sitting ready, and say
so in party chat. New timeline (T = lust used, cooldown = the 10-min
Sated debuff):

| Moment | On-screen (everyone with the addon) | Party chat (caster only) |
| --- | --- | --- |
| T | "Lust detected — timers armed" | "Lust used — back around HH:MM." |
| T+10:00 | **"Lust is up!"** + sound | **"Lust is up."** |
| T+13:00 | "Lust has been up for 3 min" + sound | "Lust has been up for 3 min." |
| T+15:00 / T+20:00 | same at 5 / 10 min | same |

`/sated marks` now means *seconds after lust comes back up* (default
still 180/300/600). `/sated` status shows "back up in 7:50 (around
HH:MM)" before ready and "lust is UP — has been up for 1:30" after.

## Design decisions (autonomy clause — flagging, not asking)

- **Chat stays caster-only.** The reminders exist to nudge a re-lust;
  if every addon user posted them, a 5-Sated party would quintuple-post.
  The caster's addon speaks; everyone else still gets the on-screen
  alerts. (Non-casters who want chat too: that's a config flag away if
  ever wanted.)
- **Combat queue holds only the newest event.** If "Lust is up" and the
  3-min mark both land during one boss fight, regen flushes **one**
  message, re-phrased from the live clock ("Lust has been up for
  3:10.") — no stale-message burst after a long pull.
- **Kept the cast-time announce** ("back around HH:MM") — it complements
  the new beats rather than conflicting; `/sated announce off` still
  silences everything.
- Per-event dedup replaced the per-window flag (`announcedKeys` on the
  window record), preserving the never-twice guarantee per event.

## Verification (machine, done)

`python tests/run_tests.py` — **51/51 pass** (suite re-timed to the new
timeline + 7 new tests):

- Ready alert fires at exactly T+10:00, not T+9:59; marks at
  ready+10/20/30s and default ready+3/5/10 min, with sounds.
- Chat: "Lust is up." lands at ready; "Lust has been up for 3 min. /
  5 min. / 10 min." at the marks; exact message text asserted.
- Ready mid-combat queues and flushes as "Lust has been up for 2:10."
  (live-clock re-phrasing); ready + mark both queued in one fight →
  exactly one flushed message.
- /reload mid-cooldown re-arms ready + marks once; /reload after ready
  refires nothing already passed; zone-in double-fire guard holds.
- Partner's lust: full on-screen alerts, zero chat.
- All carried guarantees re-verified: secret-value degradation, solo
  silence, announce on/off, reset/zone-change queue drops, debug trail
  (now includes `ready` events), ring-buffer cap.

## Verification (in-game, Jess — do this, don't skip)

Fast check without waiting 10 real minutes isn't possible for the
cooldown itself (it's anchored to the debuff length), so:

- [ ] Pop lust at a dummy, `/sated` → "back up in 9:xx (around HH:MM)".
- [ ] At 10:00: "Lust is up!" on screen + sound; if you cast it and
      are grouped: "Lust is up." in party.
- [ ] `/sated marks 10 20` beforehand if you want the up-for reminders
      seconds after ready instead of minutes (then restore
      `/sated marks 180 300 600`).
- [ ] Mid-combat ready: no chat during the fight, one re-phrased
      message after.

## Deployed

Redeployed to the AddOns folder after tests passed — `/reload` picks it
up.
