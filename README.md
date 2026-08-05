# Sated

A tiny World of Warcraft (Midnight, 12.0.x) addon that notices when
Bloodlust/Heroism-family effects are used, runs "lust back soon" timers,
and announces them to party chat. No embedded libraries.

## What it does

- **Detects lust locally.** The moment any lust hits your group, *you*
  get a Sated-family debuff — Sated watches your own debuff bar
  (`UNIT_AURA` on "player"), so it works even if nobody else in the
  group has the addon, and never touches restricted party combat data.
- **Tracks when lust can be pressed again.** The Sated debuff is the
  10-minute blocker. The addon announces **"Lust is up!"** to party chat
  when that debuff expires naturally or is removed early by an artificial
  reset (Proving Grounds, M+ start, arena gates). It then announces how
  long lust has been available at configurable marks after that moment
  (default 3, 5, and 10 minutes). There are no sounds or on-screen alert
  frames. A re-lust after a reset starts a fresh cycle, and timers survive
  `/reload` without double-firing.
- **Announces only to party chat.** The automatic messages use PARTY,
  never instance chat:
  "Lust used — back around HH:MM." at the cast,
  **"Lust is up!"** when the debuff drops, and the up-for reminders.
  By default any detected lust announces (`/sated announce all`); if
  several party members run Sated, switch to `/sated announce caster`
  so only the caster's addon speaks. Automatic chat is not sent during
  combat or an active encounter. Sated remembers only the newest pending
  milestone, then sends one message after combat and the encounter have
  both ended, re-phrased using the live clock. It does not show a local
  substitute while waiting. Chat needs a group; nothing is sent while solo.

## Commands

| Command | Effect |
| --- | --- |
| `/sated` | Show time since the last lust. While blocked, also show the remaining time and approximate ready clock time; once ready, show how long lust has been available. |
| `/sated marks 180 300 600` | Replace the reminder schedule. Values are positive seconds after the Sated-family debuff falls off, are sorted automatically, persist across sessions, and re-arm the current window. Defaults: 180, 300, and 600. |
| `/sated announce all` | Announce every lust detected from your own Sated-family debuff. This is the default, but multiple Sated users can produce duplicate party messages. `/sated announce on` is an alias. |
| `/sated announce caster` | Announce only when your character or pet cast the lust spell. Use this when several party members run Sated and you want only the caster's addon to speak. |
| `/sated announce off` | Disable automatic party messages and discard any message currently waiting for combat or the encounter to end. Detection and timer state continue internally. |
| `/sated reset` | Cancel this addon's pending timers and clear its recorded lust window. This does not remove the actual in-game debuff. |
| `/sated debug` | Print the last 20 in-memory detection, secret-value, timer, queue, and announcement events for diagnosis. The buffer resets on `/reload`. |

## Design rationale (why local-first)

Midnight killed the combat log (CLEU) for this job and made party
combat state secret. Your **own** debuff is the one signal every party
member receives the instant lust is popped, and personal buff/debuff
tracking is explicitly compliant. `UNIT_SPELLCAST_SUCCEEDED` on yourself
or your pet marks the window as yours so `announce caster` can suppress
messages from non-casters.

Known Midnight caveats baked into the design:

- **Secret values.** Every aura/spellId read passes through `Guard()`
  (`core.lua`) before any comparison. If the game hands us a secret
  value, the feature silently degrades for that instance — the addon
  never throws a lua error. Secret encounters are logged to
  `/sated debug`.
- **Chat lockdown.** No automated chat during combat or active encounters.
  Only the newest pending milestone is sent afterward, preventing a burst
  of stale messages.
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
4. Off-game test suite: `py -3 -B tests/run_tests.py` (needs
   `py -3 -m pip install lupa`; runs the addon under real Lua 5.1 with
   WoW API stubs — 60+ behavioral tests).

## Dev loop

1. Edit files in this repo, never through the AddOns folder.
2. Run `deploy.cmd` to verify that the `AddOns/Sated` junction targets
   this repository.
3. Run `/reload` in-game; junctioned edits are already live.

Sprint-by-sprint build reports (with in-game verification checklists)
live in `docs/reports/`.

## Publishing (not set up)

If this ever goes to CurseForge: the addon folder layout is already
canonical (`Sated/` containing the TOC + three lua files). A
`.pkgmeta` + zip step would go here; not built until wanted.
