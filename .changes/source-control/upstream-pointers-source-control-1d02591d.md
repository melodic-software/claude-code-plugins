---
bump: patch
---

### Fixed

- The worktree-create gate and helper no longer name `worktree.bgIsolation: "none"` as a general stand-down: that key covers background sessions only, so the messages now say so and name disabling the plugin as the stand-down for `--worktree` and subagent worktrees. The header carries a pointer record to the settings reference.
- The babysit-prs scripts no longer say sandboxed sessions serve a pinned set of GraphQL operations: the cloud GitHub proxy refuses GraphQL outright. The comments now point at the cloud-environments GitHub proxy section.

### Changed

- The native-surface records for `commit`, `pull-request` and `worktree`, the `check` skill's invocation note, the gather-block record, the babysit-loop staleness window, the worktree audit checks, the worktree-root convention and the worktree-create scripts now point at the exact Claude Code docs sections, with an as-of date and a recheck trigger, instead of quoting them. The `commit` record cites the `pull-request` record for the facts the two shared, and the auto-fix hand-off reads its preconditions from that record.
