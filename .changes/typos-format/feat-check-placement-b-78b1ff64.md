---
bump: minor
---

### Added

- A git pre-commit entry, `typos-check`, that blocks a commit only on a typo in a line the commit adds. `/typos-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The opt-in `typos_format_end_of_turn` option: when a turn ends, the same check runs over the uncommitted changes and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.
