---
bump: patch
---

### Changed

- The handoff structure reference, `/session-flow:clean-stop`, `/session-flow:recommend-skills`,
  `/session-flow:reconcile` and `/session-flow:running-retro` no longer restate upstream behavior
  (which task tools exist and what `/clear` removes, the transcript path, how `git status` and
  `git worktree remove` treat ignored files, the plugin cache layout, why a finished worker stays
  listed, what the on-disk transcript records, and when a `/loop` stops firing). Each keeps its own
  rule and links the upstream section with an as-of date and a recheck trigger.
