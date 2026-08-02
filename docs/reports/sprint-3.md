# Sprint 3 — Caster announce with combat queue

Date: 2026-08-02 · Built by Fable (Claude Code)

## What shipped

- **announce.lua:** fires only for windows tagged `mine = true` (our
  cast) with announce enabled and a group present. Out of combat with
  no active encounter → immediate
  `SendChatMessage("Lust used — back around HH:MM.", channel)`;
  channel is `INSTANCE_CHAT` when in an instance group, else `PARTY`.
  Otherwise the record is queued and flushed on
  `PLAYER_REGEN_ENABLED` / `ENCOUNTER_END`, rewritten to elapsed form:
  "Lust was used 2:10 ago — back around HH:MM." (`ENCOUNTER_START` is
  also tracked — regen between pulls mid-encounter does **not** flush.)
- **Dedup guarantees:** `record.announced` flag + one-slot queue —
  never twice per window, across repeat casts, repeat regens, and both
  event orderings (core re-notifies the announce layer when a cast
  upgrades an already-open window to `mine=true`; that was a gap in the
  original seam and is fixed in core this sprint).
- **Never solo:** no group at queue time or send time → silent drop.
- **Queue survives nothing** (per plan): in-memory only; dropped on
  zone change (`PLAYER_ENTERING_WORLD` hook), `/sated reset`, announce
  disabled, group dissolved, window expired/replaced, or reload.
- **`/sated announce on|off`** (default on), persisted to SatedDB.

## Divergences from plan

- "back around <clock time>" implemented as server-epoch → local
  `date("%H:%M")` of lust-ready time (window start + 10:00).
- Added drop-on-zone-change beyond the plan's literal list — it's the
  plan's own "queue survives nothing / stale by then" rule applied to
  leaving the instance without a regen event.

## GATE B status

Machine-side I can only verify the addon's *behavior around* the chat
API, not Blizzard's server-side acceptance. Plan expectation: chat is
permitted out of active encounters. The in-game duo check below is the
gate's ground truth. If 12.0.5+ rejects it, the failure mode is a
blocked message — the addon itself cannot error from it.

## Verification (machine, done)

`python tests/run_tests.py` — **38/38 pass** (26 carried + 12 new):

- Party cast out of combat → exactly one PARTY message matching
  `Lust used — back around H:MM.`; instance group → INSTANCE_CHAT.
- Mid-combat cast queues; regen flushes with correct "was used 2:10
  ago" phrasing at 130s.
- Encounter cast queues; ENCOUNTER_END flushes; regen mid-encounter
  keeps waiting.
- Partner's lust: chat stays silent, local timers still fire.
- Exactly-once per window: repeat casts + repeat regen; debuff-before-
  cast ordering.
- Solo: silent. `announce off/on` obeyed and persisted.
- Stale-queue drops: zone change and `/sated reset`.

## Verification (in-game, Jess — do this, don't skip)

- [ ] Duo with a partner: you cast lust out of combat in a dungeon →
      one party message, correctly formatted. **(GATE B ground truth)**
- [ ] Cast lust mid-combat → no message during combat; elapsed
      phrasing after regen.
- [ ] Partner casts lust instead → your addon stays silent in chat but
      your local timers run.

## What's deferred

- Hardening pass, `/sated debug` ring buffer, full README → Sprint 4.
