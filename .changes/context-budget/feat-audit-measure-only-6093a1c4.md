---
bump: minor
---

### Added

- `/context-budget:audit --measure-only` prints the current startup tokens per category to stdout for a read-only caller. It writes no ledger row, snapshot or other file and never installs or offers the Agent SDK. With the SDK absent it exits 4 with a one-line message and does not fall back to `cli-parse`.
