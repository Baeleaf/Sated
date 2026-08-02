# Sated — Master Build Plan
WoW Midnight (12.0.x) addon: detects Bloodlust-family use, announces to party, and runs 3/5/10-minute "lust back soon" timers.

## Locked decisions
- **Local-first detection.** The timer engine keys off the *player's own* Sated-family debuff (UNIT_AURA on "player"), not combat log or party data. CLEU is dead in 12.0 and party combat state is secret; your own debuff is the one signal every party member receives the instant lust is popped, and personal buff/debuff tracking is explicitly compliant. This means Sated works solo-installed — no one else needs it.
- **Announce = caster-only.** The chat announcement layer fires only when *you* cast a lust spell (UNIT_SPELLCAST_SUCCEEDED, unit "player"). Free deduplication: five people with the addon → one message. Non-casters still get full local timers from their debuff.
- **Queue announcements past combat.** Addon chat is locked during active encounters/M+ runs but permitted before/after. Announce immediately if out of combat; otherwise queue and flush on PLAYER_REGEN_ENABLED / ENCOUNTER_END.
- **Secret-value guards everywhere.** Every aura/spellId read is wrapped before comparison (issecretvalue-style guard, per the HexCD pattern). If a value comes back secret, degrade gracefully (skip, don't error).
- **No libraries.** No Ace3, no LibStub. This addon is ~200 lines; embedded libs are the main thing that breaks on patch day.
- **Configurable marks, default {180, 300, 600}** seconds after lust use. Stored in SavedVariables.
- **Repo at E:\git\sated, deployed by .cmd script** (robocopy to the AddOns folder). Dev loop is edit → deploy.cmd → /reload in-game.

## How to run this plan
Save the Standing Brief below as `BUILD_BRIEF.md` in the repo. Paste one sprint block at a time into Claude Code. Fable writes reports to `docs/reports/sprint-N.md` (shape: What shipped / What you need to do once / What's deferred / Verification). Commits map 1:1 to sprints: `Sprint 2: timer engine + local alerts`.

VERIFY steps here are in-game and human-run — there is no headless WoW. Each sprint's VERIFY is a checklist Jess executes at the character select / target dummy level and records in the sprint report.

---

# STANDING BRIEF (save as BUILD_BRIEF.md)

# BUILD_BRIEF.md — Sated (codename: Sated)

## Stack & environment
- Lua 5.1 (WoW's embedded interpreter — no goto, no bit ops without bit lib, 1-indexed everything).
- Target: WoW Retail, Midnight 12.0.x. **Interface version in the TOC is read from an installed, currently-working addon during Recon — never guessed.**
- Machine: Windows 11. Repo at `E:\git\sated`. WoW AddOns path discovered in Sprint 0 Recon (typically `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`).
- No build step, no dependencies, no package manager. Files: `Sated.toc`, `core.lua`, `config.lua`, `announce.lua`, `deploy.cmd`.
- SavedVariables: `SatedDB` (declared in TOC).

## The autonomy clause (applies to every sprint)
Work autonomously to completion. Do not stop to ask for confirmation on reversible implementation choices — pick the sound default, note it in your summary, and keep going. Never: add embedded libraries, switch detection strategy away from self-aura, or write to files outside E:\git\sated and the deploy target.

## The Recon → Build → Verify contract
Every sprint runs RECON (read before writing), BUILD, VERIFY (do this, don't skip — VERIFY here is a checklist Jess runs in-game), and reports divergences from the plan.

## Divergence rules (do NOT break these without flagging)
- All spell/debuff IDs live in `config.lua` as data tables. Zero magic numbers in `core.lua` or `announce.lua`.
- Every read of aura data or cast spellIds passes through `Guard()` in core.lua (the secret-value wrapper) before any comparison or arithmetic. No naked comparisons on API-returned combat values.
- The addon must never error when a value is secret — degrade to "feature silently unavailable this instance."
- No automated chat during combat. The announce queue is the only path to SendChatMessage.

## Locked decisions (do not relitigate)
See master plan header. In brief: local-first self-debuff detection; caster-only announce; post-combat queue; no libs; marks configurable, default 3/5/10 min.

## Decision gates
- **⚠️ GATE A (resolve in Sprint 0 Recon, blocks everything):** In current 12.0.x, confirm in an instanced context that spellId comparison on the player's OWN auras is not secret. Test: in a follower dungeon or M+ (not open world — restrictions only apply to instanced content), `/dump` an aura query on "player" and check whether the returned spellId can be compared to a number without erroring. If secret → fallback design: match by totem/aura *name* if exposed, or anchor on the Blizzard cooldown-viewer signal; flag for redesign before Sprint 1.
- **⚠️ GATE B (resolve before Sprint 3):** Confirm SendChatMessage to PARTY works out-of-combat inside a dungeon on current patch (the comms lockdown was scoped to active encounters, but 12.0.5 tightened cooldown-tracker territory — verify, don't assume).

## Data (source of truth — verify IDs in-game during Recon, adapt if renamed)
```lua
-- config.lua
Sated.LUST_CASTS = {      -- spellIds that trigger the announce layer (you cast these)
  [2825]   = "Bloodlust",            -- Shaman (Horde)
  [32182]  = "Heroism",              -- Shaman (Alliance)
  [80353]  = "Time Warp",            -- Mage
  [264667] = "Primal Rage",          -- Hunter pet
  [390386] = "Fury of the Aspects",  -- Evoker
  -- Recon: check for drum items / new Midnight lust sources and add
}
Sated.SATED_DEBUFFS = {   -- self-debuffs that start the timer engine
  [57724]  = true,  -- Sated (Bloodlust)
  [57723]  = true,  -- Exhaustion (Heroism)
  [80354]  = true,  -- Temporal Displacement (Time Warp)
  [264689] = true,  -- Fatigued (Primal Rage)
  [390435] = true,  -- Exhaustion (Fury of the Aspects)
}
Sated.DEFAULT_MARKS = { 180, 300, 600 }  -- seconds after lust
```

## Guardrails carried throughout
- These IDs and the API surface are a moving target per patch — the addon's posture is "fail silent, log to a /sated debug buffer," never lua errors in a key.
- SavedVariables writes only on PLAYER_LOGOUT or settings change; no per-frame writes.
- deploy.cmd copies repo → AddOns dir one-way. Never edit in the AddOns dir directly.

---

# PHASE 1 — SKELETON & DETECTION

## Sprint 0 — Recon & scaffold
### RECON
- Locate the WoW install and AddOns directory on this machine; record the path.
- Open the .toc of one currently-working installed addon and record its `## Interface:` number — this is our TOC number.
- List which lust-adjacent addons are already installed (OmniCD? HexCD?) — for reference, not dependency.
### BUILD
- Create `E:\git\sated` with: `Sated.toc` (Interface from recon, SavedVariables: SatedDB, load order config→core→announce), `config.lua` (tables verbatim from brief), `core.lua` (addon frame, event registration stub, `Guard()` secret-value wrapper, `/sated` slash command that prints "Sated loaded, no lust recorded"), empty `announce.lua`, `deploy.cmd` (robocopy repo → AddOns\Sated), `README.md`, git init + first commit.
- `Guard(v)`: returns nil if the value is secret or non-comparable; else returns v. Implement using the current API's secrecy predicate discovered in recon (issecretvalue or successor — check warcraft.wiki.gg if uncertain, note the source).
### VERIFY (do this, don't skip — Jess, in-game)
- [ ] Run deploy.cmd, launch WoW: Sated appears in the addon list, loads with no error.
- [ ] `/sated` prints the loaded message.
- [ ] **GATE A test:** enter a follower dungeon. `/dump` a player aura query; confirm own-aura spellIds compare without erroring. Record result in sprint report. **If secret, stop — redesign before Sprint 1.**

## Sprint 1 — Detection engine
### RECON
- Read core.lua and config.lua as committed. Check warcraft.wiki.gg's 12.0.0 API changes page for the current aura-scan API (UNIT_AURA payload changed repeatedly; use the incremental update payload if available rather than full rescans).
### BUILD
- Register UNIT_AURA filtered to "player". On update, scan (or delta-scan) for any SATED_DEBUFFS id via Guard().
- On first detection: record `SatedDB.lastLust = { at = GetTime(), server = GetServerTime() }`, print a local confirmation line ("Lust detected — timers armed"). Ignore re-detections while a lust window is already recorded within the debuff's duration.
- Also register UNIT_SPELLCAST_SUCCEEDED ("player") against LUST_CASTS — sets the same record plus `SatedDB.lastLust.mine = true` (feeds Sprint 3; announce.lua stays empty).
- `/sated` now reports: time since last lust, mm:ss.
### VERIFY (do this, don't skip)
- [ ] On a lust-capable character (or with a friendly shaman at a dummy): pop lust → chat line appears, `/sated` shows a running clock.
- [ ] Someone ELSE pops lust → same result (debuff path, not cast path).
- [ ] /reload mid-window → `/sated` still shows correct elapsed time (persisted via GetServerTime delta).

# PHASE 2 — TIMERS & LOCAL ALERTS

## Sprint 2 — Timer engine + alerts
### RECON
- Read core.lua as committed; read SatedDB persistence shape.
### BUILD
- On lust detection, schedule C_Timer.After for each mark in `SatedDB.marks or DEFAULT_MARKS` (compute remaining marks correctly after /reload from the persisted timestamp).
- Each mark fires: RaidNotice-style on-screen text via a dedicated message frame ("Lust used 5:00 ago") + PlaySound (pick a stock sound kit id; note it in the report). Marks past 10:00 also clear the active window.
- `/sated marks 180 300 600` sets custom marks; `/sated sound on|off`, `/sated reset`. All persisted to SatedDB.
- Keep the alert path pure-local: no chat, no comms, works in combat (on-screen text + sound are display-only and unrestricted).
### VERIFY (do this, don't skip)
- [ ] `/sated marks 10 20 30` then pop lust at a dummy: three alerts land at 10/20/30s with sound.
- [ ] /reload at ~15s: the 20s and 30s alerts still fire, the 10s one doesn't double-fire.
- [ ] Alerts fire while actively in combat with the dummy (display path unaffected by restrictions).
- [ ] Restore real marks; settings survive a full logout.

# PHASE 3 — PARTY ANNOUNCE

## Sprint 3 — Caster announce with combat queue
### RECON
- Read core.lua's `mine` flag path. **GATE B:** confirm current-patch behavior of SendChatMessage("...", "PARTY") out-of-combat inside an instance (check wiki changelog for 12.0.5+ notes; final confirmation is the in-game VERIFY).
### BUILD
- announce.lua: when a lust window opens with `mine = true` and announce is enabled — if not in combat and no active encounter: SendChatMessage("Lust used — back around <clock time>.", party/instance channel as appropriate). Else push onto a queue; flush on PLAYER_REGEN_ENABLED / ENCOUNTER_END with the message rewritten to elapsed form ("Lust was used 2:10 ago — back around <time>").
- Guard: never announce twice per window; never announce solo; `/sated announce on|off` (default on).
- Queue survives nothing — if the run ends before regen, drop it silently (stale info by then).
### VERIFY (do this, don't skip)
- [ ] Duo with a partner (or second account): you cast lust out of combat in a dungeon → one party message, correctly formatted.
- [ ] Cast lust mid-combat → no message during combat; message with elapsed phrasing after regen.
- [ ] Partner casts lust instead → your addon stays silent in chat but your local timers run.

# PHASE 4 — HARDENING & SHIP

## Sprint 4 — Patch-resilience + polish
### RECON
- Reread all three lua files; grep for any comparison on API-returned values not routed through Guard().
### BUILD
- Wrap every remaining seam; add `/sated debug` ring buffer (last 20 events: detections, secrets encountered, queue actions) for patch-day diagnosis.
- README: what it does, the local-first design rationale, known Midnight API caveats, and a "when a patch breaks it" triage section pointing at config.lua IDs and the debug buffer.
- Optional (seam only, no implementation this phase): a `pkgmeta`/zip step for CurseForge if Jess ever wants to publish — stub the folder layout note in README, don't build tooling.
### VERIFY (do this, don't skip)
- [ ] Full happy path in one M+ or follower dungeon run: detection, all three timers, post-combat announce.
- [ ] `/sated debug` shows a sane event trail for that run.
- [ ] Zero lua errors across the session with a error-display addon (BugSack or `/console scriptErrors 1`).
