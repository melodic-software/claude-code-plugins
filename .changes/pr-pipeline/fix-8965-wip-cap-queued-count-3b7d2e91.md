---
bump: patch
---

### Fixed

- The queued count no longer counts an issue twice when a person edits its lane PR's first body line: an open lane PR whose first line names no issue is matched by its `work-resolve-issue/issue-<n>-...` head branch, at one pull request read each.
- work-unblock's `label-unblocked` job runs one at a time across the repository, so a burst of closes or a close run beside the hourly sweep can no longer each admit the queued cap's whole room.

### Changed

- The pr-pipeline README's WIP cap section names each `agent-ready` writer and whether the queued cap paces it: only work-unblock's new labels are paced.
