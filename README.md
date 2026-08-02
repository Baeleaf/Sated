# Sated

A tiny World of Warcraft (Midnight, 12.0.x) addon that notices when
Bloodlust/Heroism-family effects are used, runs "lust back soon" timers,
and announces your own lust casts to the party. ~350 lines, no libraries.

## What it does

- **Detects lust locally.** The moment any lust hits your group, *you*
  get a Sated-family debuff — Sated watches your own debuff bar
  (`UNIT_AURA` on "player"), so it works even if nobody else in the
  group has the addon, and never touches restricted party combat data.
- **Timers.** On-screen alert + sound at configurable marks after lust
  (default 3:00, 5:00, 10:00 — the 10-minute mark is when lust is
  usable again). Marks survive `/reload` without double-firing.
- **Caster-only announce.** If *you* cast the lust, one party/instance
  chat message: "Lust used — back around HH:MM." Five addon users, one
  message. During combat or an encounter the message queues and is sent
  after, rephrased to "Lust was used 2:10 ago — back around HH:MM."

## Commands

| Command | Effect |
| --- | --- |
| `/sated` | Time since last lust |
| `/sated marks 180 300 600` | Set alert marks (seconds after lust) |
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
