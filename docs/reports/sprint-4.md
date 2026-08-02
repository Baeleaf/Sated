# Sprint 4 — Hardening & ship

Date: 2026-08-02 · Built by Fable (Claude Code)

## What shipped

- **Guard audit (recon):** grepped all lua for API-value reads outside
  `Guard()`. Findings: `aura.spellId` and cast `spellId` were already
  routed; `updateInfo.isFullUpdate` was the one exposed seam — **and
  the audit's new test caught a real bug in my first fix**: guarding
  the flag to nil made a *secret* flag read as "incremental update,"
  silently skipping the safe rescan. Final behavior: a secret
  `isFullUpdate` counts as a full update (rescan path), with
  `issecretvalue` the only operation performed on the secret. Duration
  and expirationTime are never read anywhere; unit args come from
  `RegisterUnitEvent`-filtered registrations.
- **`/sated debug` ring buffer:** last 20 events, in-memory —
  detections (mine/party), secrets encountered (labeled by read site,
  contents never stored), marks fired, announce queued/sent/dropped,
  resets. Empty-buffer and 20-cap behavior tested.
- **README (full):** what it does, the local-first rationale, Midnight
  API caveats, commands table, patch-day triage (debug buffer →
  config.lua IDs → TOC bump → test suite), dev loop, and the
  CurseForge seam note (layout only, no tooling — per plan).
- **Version → 1.0.0** in the TOC.

## Divergences from plan

- None new this sprint. Cumulative divergences: repo path/remote (per
  Jess), pet-unit cast watching, `NewTimer` over `After`, off-game test
  harness, queue-drop on zone change — all flagged in earlier reports.

## Verification (machine, done)

`python tests/run_tests.py` — **43/43 pass** (38 carried + 5 new):

- Full happy-path run in one test: group + combat cast + debuff +
  marks + regen → debug trail shows detect/mark/queue/announce in
  order (the machine version of the plan's "sane event trail" check).
- Secret aura, cast, and isFullUpdate reads all logged and degraded;
  secret full-update flag still detects via rescan.
- Ring buffer caps at exactly 20, evicts oldest, keeps newest.
- Plus the full carried suite: detection orderings, timer/reload
  math, announce dedup/queue/drop behavior.

Zero lua errors across all 43 environments (any error fails the run —
this is the off-game stand-in for the BugSack check).

## Verification (in-game, Jess — do this, don't skip)

- [ ] Full happy path in one M+ or follower dungeon run: detection,
      all three timers, post-combat announce.
- [ ] `/sated debug` shows a sane event trail for that run.
- [ ] Zero lua errors across the session with BugSack or
      `/console scriptErrors 1`.
- [ ] Plus the still-open gates: **GATE A** (sprint 0 report) and
      **GATE B** (sprint 3 report).

## What's deferred

- CurseForge packaging (seam noted in README, no tooling by design).
- Drum items / any new Midnight lust sources → add to `config.lua`
  when confirmed in-game.
