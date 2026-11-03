---
bump: patch
---

### Changed

- The issue lane closes a `report-delivered` stop on any issue the run committed nothing for, whatever its work class or with none, and still retries when the run committed to a branch. Before, only a `work-class: read-only` issue closed (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)). Such a close still counts for nothing as a trusted close for a dependent.
