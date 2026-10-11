---
bump: minor
---

### Added

- **The `/harness-ops:plugins` stale-project-records section names where to act.** When the report lists project records whose paths are not present on this machine, its last rows point project-scope records left by worktrees removed under the source-control worktree root at `/source-control:worktree audit (if installed)`, which classifies them and gives the gated reap. The section still reaps nothing, counts nothing as a divergence and calls no path dead; the rows only name the command that owns the remedy. The stale-records golden covers the row (#6184).
