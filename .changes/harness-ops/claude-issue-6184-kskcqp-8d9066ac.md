---
bump: minor
---

### Added

- **The `/harness-ops:plugins` stale-project-records section names where to act.** When the report lists project records whose paths are not present on this machine, its last row now points at `/source-control:worktree audit (if installed)`, which classifies the records left by removed worktrees and owns the gated reap. The section still reaps nothing, counts nothing as a divergence and calls no path dead; the row only names the command that owns the remedy. The stale-records golden covers the row (#6184).
