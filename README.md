# Sated

WoW Midnight (12.0.x) addon: detects Bloodlust-family use, announces to party,
and runs 3/5/10-minute "lust back soon" timers.

**Status: Sprint 0 — skeleton.** Full README lands in Sprint 4.

## Dev loop

1. Edit files in this repo (never in the AddOns folder).
2. Run `deploy.cmd` (robocopy → `E:\World of Warcraft\_retail_\Interface\AddOns\Sated`).
3. `/reload` in-game.

## Verification

Off-game harness (Lua 5.1 via `lupa`, stubs for the WoW API):

```bash
python tests/run_tests.py
```

In-game checklists per sprint live in `docs/reports/`.
