---
bump: patch
---

### Fixed

- `/harness-ops:plugins` references: `marketplace remove`'s flag and data-cleanup records follow the
  current CLI reference and `--help`, the uninstall option record no longer restates a list, and the
  monitors pointer moves to the section that says it.
- `/harness-ops:lanes` refresh: a `/loop` fire is treated as not delivering a skill edit, without
  claiming a repeat invocation never appends changed content.
- `/harness-ops:audit-performance` and `/harness-ops:observability`: the per-hook timing records name
  the documented debug-log durations and why transcripts stay the source.
- `audit_skill_visibility.py`: its listing-default and `enabledPlugins` records cite the sections
  that state them, and a `disable-model-invocation` spelled `yes`, `on` or `1` now counts as true.
- `/harness-ops:audit-performance`: the stale-session advisory names `/reload-plugins` as well as a
  restart.
