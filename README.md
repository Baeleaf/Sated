# Sated

A tiny World of Warcraft (Midnight, 12.0.x) addon that notices when
Bloodlust/Heroism-family effects are used, runs "lust back soon" timers,
and announces your own lust casts to the party. ~350 lines, no libraries.

## What it does

- **Detects lust locally.** The moment any lust hits your group, *you*
  get a Sated-family debuff — Sated watches your own debuff bar
  (`UNIT_AURA` on "player"), so it works even if nobody else in the
  group has the addon, and never touches restricted party combat data.
- **Tracks when lust can be pressed again.** The Sated debuff is the
  10-minute blocker; the moment it actually leaves your bar you get
  **"Lust is up!"** with sound — whether it expired naturally or was
  wiped early by an artificial reset (Proving Grounds, M+ start, arena
  gates). Then reminders of how long lust has been sitting available at
  configurable marks after that moment (default 3, 5, and 10 minutes):
  **"Lust has been up for 3 min"**, and so on. A re-lust after a reset
  starts a fresh cycle. All timers survive `/reload` without
  double-firing, including reloads that straddle a reset.
- **Announces to party chat.** Every beat also goes to party chat
  (always PARTY, never instance chat) automatically:
  "Lust used — back around HH:MM." at the cast,
  **"Lust is up."** when the debuff drops, and the up-for reminders.
  By default any detected lust announces (`/sated announce all`); if
  several party members run Sated, switch to `/sated announce caster`
  so only the caster's addon speaks. During combat or an encounter,
  messages queue (newest beat only) and are sent after regen/encounter
  end, re-phrased from the live clock. Chat needs a group — WoW has no
  channel to announce to while solo.

## Commands

| Command | Effect |
| --- | --- |
| `/sated` | Time since last lust / how long lust has been up |
| `/sated marks 180 300 600` | Set reminder marks (seconds after the debuff falls off) |
| `/sated sound on\|off` | Alert sound (default on) |
| `/sated announce all\|caster\|off` | Party announce (default all) |
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
