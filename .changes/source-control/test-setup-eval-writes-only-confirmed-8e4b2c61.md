---
bump: patch
---

### Added

- Plugin-eval case `setup-writes-only-confirmed-change`: `/source-control:setup apply layer=team` runs in a scratch repository where the prompt confirms the team convention file and declines the personal overlay and the neutral convention file. Deterministic `file_exists` graders fail when either declined file appears in the workspace.
