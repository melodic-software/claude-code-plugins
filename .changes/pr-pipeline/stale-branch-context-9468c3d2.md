---
bump: minor
---

### Added

- A work-resolve-issue run that starts fresh because the earlier run's lane branch is behind the
  default branch now gives the model that branch's work. `report-outcome --find-prior` outputs
  `stale-branch` and `stale-tip` (the tip it checked every commit of), and `write-issue.mjs` adds
  `stale_branch` to `issue.json`: the branch, the tip, each commit's subject and the files it
  changed, from the same capped `GET /compare` a resume uses, as data. report-outcome names the
  branch on the issue once, in a comment opening with
  `<!-- work-resolve-issue stale-branch=<branch> -->`, and deletes no branch
  ([#9468](https://github.com/melodic-software/claude-code-plugins/issues/9468)).
