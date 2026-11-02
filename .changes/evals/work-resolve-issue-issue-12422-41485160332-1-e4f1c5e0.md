---
bump: patch
---

### Fixed

- `run-validity.py`'s `session started` check fails a 0-turn run whose trace shows a skill's pre-computed command failing (`Shell command failed for pattern` in a `local-command-stderr`), even when the trace holds assistant messages, so the run reads as a harness failure, not a forked session or a scored miss (#12422).
- `plugin-eval` records a Claude Code 2.1.316 gotcha: a case that types a slash command for a skill with a pre-computed line ends at 0 turns and 0 cost, and the Skill tool route avoids it, with a recheck trigger in `records.md` (#12422).
