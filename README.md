# Sated

A tiny World of Warcraft (Midnight, 12.0.x) addon that notices when
Bloodlust/Heroism-family effects are used, runs "lust back soon" timers,
and announces your own lust casts to the party. ~350 lines, no libraries.

## What it does

- **Detects lust locally.** The moment any lust hits your group, *you*
  get a Sated-family debuff — Sated watches your own debuff bar
  (`UNIT_AURA` on "player"), so it works even if nobody else in the
  group has the addon, and never touches restricted party combat data.
- **Knows when lust is back up.** The Sated debuff is the 10-minute
  cooldown; when it ends you get an on-screen **"Lust is up!"** alert +
  sound, then reminders of how long it's been sitting ready at
  configurable marks (default 3, 5, and 10 minutes after it came back
  up). All timers survive `/reload` without double-firing.
- **Caster-only announce.** If *you* cast the lust, the same beats go
  to party/instance chat: "Lust used — back around HH:MM." at the cast,
  **"Lust is up."** when the cooldown ends, and **"Lust has been up for
  3 min."** at each mark. Five addon users, one message per event.
  During combat or an encounter, messages queue (newest event only) and
  are sent after regen/encounter end, re-phrased from the live clock.

## Commands

| Command | Effect |
| --- | --- |
| `/sated` | Time since last lust / how long lust has been up |
| `/sated marks 180 300 600` | Set reminder marks (seconds after lust comes back up) |
| `/sated sound on\|off` | Alert sound (default on) |
| `/sated announce on\|off` | Party announce (default on) |
| `/sated reset` | Clear the current lust window |
| `/sated debug` | Last 20 internal events (patch-day diagnosis) |

## Design rationale (why local-first)

Midnight killed the combat log (CLEU) for this job and made party
combat state secret. Your **own** debuff is the one signal every party
member receives the instant lust is popped, and personal buff/debuff
tracking is explicitly compliant. The chat announcement fires only from
`UNIT_SPELLCAST_SUCCEEDED` on yourself (and your pet, for Primal Rage)
— free deduplication.

Known Midnight caveats baked into the design:

- **Secret values.** Every aura/spellId read passes through `Guard()`
  (`core.lua`) before any comparison. If the game hands us a secret
  value, the feature silently degrades for that instance — the addon
  never throws a lua error. Secret encounters are logged to
  `/sated debug`.
- **Chat lockdown.** No automated chat during active encounters; the
  post-combat queue is the only path to `SendChatMessage`.
- **SavedVariables** (`SatedDB`) are written by the client at logout —
  the addon does no per-frame persistence.

## When a patch breaks it

1. `/sated debug` — look for `secret` entries (API made something
   secret that wasn't) or an empty trail after a lust (event payload
   changed).
2. All spell/debuff IDs live in **`config.lua`** as data tables —
   renamed or new lust spells (drums, new classes) get added there,
   never in core.
3. Bump `## Interface:` in `Sated.toc` by copying the number from any
   currently-working addon's TOC.
4. Off-game test suite: `python tests/run_tests.py` (needs
   `pip install lupa`; runs the addon under real Lua 5.1 with WoW API
   stubs — 40+ behavioral tests).

## Dev loop

1. Edit files in this repo (never in the AddOns folder).
2. Run `deploy.cmd` (robocopy → `E:\World of Warcraft\_retail_\Interface\AddOns\Sated`).
3. `/reload` in-game.

Sprint-by-sprint build reports (with in-game verification checklists)
live in `docs/reports/`.

## Publishing (not set up)

If this ever goes to CurseForge: the addon folder layout is already
canonical (`Sated/` containing the TOC + three lua files — exactly what
`deploy.cmd` produces). A `.pkgmeta` + zip step would go here; not
built until wanted.
