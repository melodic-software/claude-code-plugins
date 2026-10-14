---
bump: minor
---

### Changed

- Shorter descriptions for `audit-install-state`, `audit-native-overlap`, `audit-performance`, `behavior-probes`, `changelog`, `inventory`, `known-issues`, `machine-profile`, `morning-brief` and `observability`, and tighter bodies for `audit-performance`, `inventory`, `known-issues`, `morning-brief` and `observability`. Every gate, stop, command and report line stays.

### Fixed

- `/harness-ops:audit-install-state`'s "Run it" command now passes `--root <root>`, so the engine audits the tree the user named instead of falling back to `$CLAUDE_CONFIG_DIR` or `~/.claude`.

### Added

- Eleven outcome eval cases under `evals/`, one per audited skill, and frozen trigger-probe sets for thirteen skills under `probes/`.
