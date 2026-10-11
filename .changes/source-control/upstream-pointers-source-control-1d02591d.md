---
bump: patch
---

### Fixed

- The worktree-create gate and helper no longer name `worktree.bgIsolation: "none"` as a general stand-down: that key covers background sessions only, so the messages now say so and name disabling the plugin as the stand-down for `--worktree` and subagent worktrees. The header carries a pointer record to the settings reference.
- The babysit-prs scripts no longer say sandboxed sessions serve a pinned set of GraphQL operations: the cloud GitHub proxy refuses GraphQL outright. The comments now point at the cloud-environments GitHub proxy section.
