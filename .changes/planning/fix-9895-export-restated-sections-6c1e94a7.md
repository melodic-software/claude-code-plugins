---
bump: patch
---

### Fixed

- **`interview` surface:** `export-brief` no longer drops three sections of a confirmed restatement. Its `decisions` recap becomes a `### Decisions` section, and its `deferred` and `planningOwned` bullets join `### Deferred questions` after the register's retired rows, tagged **arbiter: /planning:plan**, or **arbiter: USER-RESERVED** when a bullet leads with a user-reserved row's `Q<N>` or says USER-RESERVED, so `/planning:plan` sees them ([#9895](https://github.com/melodic-software/claude-code-plugins/issues/9895)).
