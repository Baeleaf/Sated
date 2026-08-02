# Sprint 9 — Party chat only

Date: 2026-08-02 · Built by Fable (Claude Code) · Jess's request after
in-game testing.

## What changed

One-line behavior change: the announce channel is now **always PARTY**,
never INSTANCE_CHAT. Previously the addon followed the common addon
convention of preferring instance chat inside queued/instance-type
groups, which is where Jess's warnings were landing.

## Caveat worth knowing

In a pure matchmade group of strangers (LFG queue with no pre-formed
party), WoW routes group text through instance chat; a PARTY send there
may not reach the group. For Jess's use (pre-formed party running
content together) PARTY is correct and is what she asked for. If the
LFG case ever matters, a `/sated channel party|instance|auto` toggle is
a five-line addition.

## Verification (machine, done)

`python tests/run_tests.py` — **62/62 pass**. The instance-group test
now asserts the message goes to PARTY even when only an instance-type
group exists; every other chat test already asserted PARTY.

## Verification (in-game, Jess)

Deployed — `/reload`.

- [ ] Same flow as before in your group: all warnings ("Lust used…",
      "Lust is up.", "Lust has been up for…") now appear in party chat,
      not instance chat.
