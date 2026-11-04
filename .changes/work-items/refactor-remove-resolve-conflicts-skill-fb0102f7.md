---
bump: patch
---

### Changed

- `/work-items:ship run` resolves a merge conflict on the integration branch under `/source-control:pull-request ready`'s base-merge rules, since source-control's `resolve-conflicts` skill is removed ([#13199](https://github.com/melodic-software/claude-code-plugins/issues/13199)).
