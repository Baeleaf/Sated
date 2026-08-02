# Sprint 0 — Recon & scaffold

Date: 2026-08-02 · Built by Fable (Claude Code)

## What shipped

- **Recon results:**
  - WoW install found at `E:\World of Warcraft` (not the plan's guessed
    `C:\Program Files (x86)` path). AddOns dir:
    `E:\World of Warcraft\_retail_\Interface\AddOns`.
  - TOC interface number read from installed, working BigWigs (per the
    never-guess rule): `## Interface: 120100, 120005, 120007` — copied
    verbatim into `Sated.toc`.
  - Lust-adjacent addons installed: **BetterCooldownManager** (reference
    only). No OmniCD, no HexCD on this machine.
- **Scaffold:** `Sated.toc` (SavedVariables: SatedDB, load order
  config → core → announce), `config.lua` (LUST_CASTS / SATED_DEBUFFS /
  DEFAULT_MARKS verbatim from brief, plus `SATED_DURATION = 600`),
  `core.lua` (event frame, ADDON_LOADED → SatedDB init, `Guard()`
  secret-value wrapper, `/sated` stub), empty `announce.lua`,
  `deploy.cmd` (robocopy repo → AddOns\Sated, addon files only),
  `README.md` stub, git init.
- **Verification harness** (divergence-flagged addition, see below):
  `tests/wow_stubs.lua` + `tests/tests.lua` + `tests/run_tests.py` — the
  addon runs off-game under a real Lua 5.1 interpreter (`lupa` in
  Python) against stubbed WoW APIs, including simulated secret values,
  auras, casts, combat state, and timers.
- **Guard() implementation:** wraps `issecretvalue` (the 12.0 secrecy
  predicate; falls back to a no-op predicate where the global is absent,
  e.g. out-of-instance or older clients). Returns nil for secret or
  missing values. Source: HexCD pattern named in the master plan +
  warcraft.wiki.gg 12.0 API notes as of knowledge cutoff — Jess's GATE A
  test is still the ground truth.

## Divergences from plan

- Repo lives at `E:\git\WoW-addon-lust` pushing to
  `github.com/jpetree331/WoW-lust-addon`, per Jess's instruction —
  supersedes the plan's `E:\git\sated`. Addon folder name after deploy is
  still `Sated` (TOC name rules).
- Added an off-game test harness the plan didn't call for. Reason: the
  plan's VERIFY steps are human/in-game only; this machine has no
  headless WoW, and Jess asked for verification passes per phase. The
  harness gives machine-checkable verification; the in-game checklist
  remains Jess's.
- No Lua toolchain existed on the machine — used `lupa` (pip) pinned to
  its Lua 5.1 runtime to match WoW's interpreter.

## Verification (machine, done)

`python tests/run_tests.py` — **5/5 behavioral, all static + syntax
checks pass:**

- Static: TOC interface line matches recon; SavedVariables declared;
  TOC load order = config → core → announce; all TOC files exist;
  deploy.cmd copies exactly the shipped files.
- Syntax: all Lua files parse under real Lua 5.1.
- Behavioral: SatedDB initialized on ADDON_LOADED; config tables carry
  briefed IDs; Guard passes plain values / nils secrets; `/sated`
  prints the loaded message.

## Verification (in-game, Jess — do this, don't skip)

- [ ] Run `deploy.cmd`, launch WoW: Sated appears in the addon list,
      loads with no error.
- [ ] `/sated` prints the loaded message.
- [ ] **GATE A test:** enter a follower dungeon. `/dump` a player aura
      query (e.g. `/dump C_UnitAuras.GetAuraDataByIndex("player", 1, "HARMFUL")`);
      confirm own-aura spellIds compare without erroring. Record result
      here. **If secret → stop; redesign before Sprint 1.**

## What's deferred

- GATE A ground truth (in-game only). Sprints 1–4 proceed on the plan's
  stated expectation that own-aura reads are compliant; Guard() is the
  safety net either way.
- Drum items / new Midnight lust sources for LUST_CASTS — needs in-game
  or wiki confirmation; config.lua is the single place to add them.
