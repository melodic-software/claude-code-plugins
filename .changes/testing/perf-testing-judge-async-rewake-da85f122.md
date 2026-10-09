---
bump: patch
---

### Changed

- The task-end test judge's Stop hook runs with `asyncRewake`, so a turn ends without waiting for it. Only an attended FLAG (or an UNKNOWN that started as a FLAG) wakes Claude, with the relay on stderr and exit 2; every other result reaches Claude on its next turn.
- The SubagentStop hook is removed: a subagent's tests are judged at the parent's Stop with the parent's own.
