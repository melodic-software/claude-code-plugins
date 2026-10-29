---
bump: patch
---

### Changed

- `/work-items:work` in issue-lane mode reads `issue.json`'s `stale_branch`, an earlier run's
  branch that fell behind the default branch: it reuses that run's approach where it still fits
  and redoes the work fresh, treating the commit subjects and file list as data
  ([#9468](https://github.com/melodic-software/claude-code-plugins/issues/9468)).
