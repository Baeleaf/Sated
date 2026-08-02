# Sprint 6 — Marks since use + automatic party chat

Date: 2026-08-02 · Built by Fable (Claude Code) · Fixes Jess's two
in-game reports against the Sprint 5 build.

## The two reports, diagnosed

1. **"Warns after 10 seconds; needs 3/5/10 MINUTES."** Two causes
   stacked: the 10/20/30-second *test marks* from the walkthrough were
   still saved in SatedDB, and Sprint 5 had moved the marks to *after*
   the cooldown ended (T+13/15/20 min) — not what was wanted.
2. **"Needs to write the warning automatically into party chat."**
   Sprint 3–5 chat was caster-only by design, so windows opened by
   someone else's lust (or tests without a cast) never chatted.

## What shipped

- **Marks are seconds since lust USE again** (default 180/300/600).
  Pre-cooldown marks warn as countdowns — "Lust back in 7 min" /
  "Lust back in 5 min" — and the 10-minute moment is "Lust is up!"
  (a mark equal to the cooldown folds into the ready alert; marks set
  past it read "Lust has been up for X"). On-screen + sound as before.
- **Chat on every beat, for every detected lust, by default.** New
  announce modes: `all` (default — whoever cast it), `caster` (only
  our own casts; the old dedup behavior for groups where several
  people run Sated), `off`. Chat lines: "Lust used — back around
  HH:MM." → "Lust back in 7 min." → "Lust back in 5 min." →
  "Lust is up."
- **Settings schema v2 with migration:** on first load the addon wipes
  pre-v2 `marks`/`announce` values and stamps `schema = 2` — Jess's
  leftover 10/20/30 test marks clean themselves up, no manual step.
- Combat queue unchanged: chat still can't be sent during active
  combat/encounters (Blizzard restriction), so mid-fight beats queue
  (newest only) and flush after, re-phrased from the live clock
  ("Lust back in 5:50."). On-screen alerts are never delayed.
- README updated (including the note that chat needs a group — WoW has
  no channel for solo announcements, which may have been part of the
  silent test).

## Verification (machine, done)

`python tests/run_tests.py` — **53/53 pass** (suite re-timed + new):

- Default marks: exact alerts at T+3:00 ("Lust back in 7 min"),
  T+5:00 ("Lust back in 5 min"), T+10:00 ("Lust is up!") — and the
  matching chat lines, exact text asserted.
- v2 migration: stale `{10,20,30}` marks and old announce flag wiped,
  schema stamped.
- Mode `all`: partner's lust gets the full chat pipeline; mode
  `caster`: partner silent, own cast speaks; `off` silences all.
- Queued countdown mark flushes re-phrased ("Lust back in 5:50." after
  a 250s fight); multiple beats in one fight flush as one message.
- All carried guarantees: reload/zone-in no-double-fire (re-timed),
  secret-value degradation, solo silence, exactly-once per beat,
  debug trail, ring-buffer cap.

## Verification (in-game, Jess)

Deployed — just `/reload`. Your old test marks are auto-wiped by the
migration, so no cleanup needed.

- [ ] Pop lust (anyone's) while grouped: party chat gets "Lust used —
      back around HH:MM." then "Lust back in 7 min." at 3:00,
      "Lust back in 5 min." at 5:00, "Lust is up." at 10:00 — with the
      matching on-screen warnings.
- [ ] Same beats mid-combat: on-screen on time, chat arrives after the
      fight, re-phrased.
- [ ] `/sated` mid-cooldown shows "back up in X (around HH:MM)".

## Notes

- Solo = no chat, by WoW's rules (no channel to send to); on-screen
  alerts always work.
