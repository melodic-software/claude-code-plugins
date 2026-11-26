---
bump: patch
---

### Fixed

- The cost-decision carry no longer refuses a range of more than 250 commits. `merge-holds.mjs` `carries` and ci-status's cost-hold step read a compare whose unpaged commit list stops short of `total_commits` again in pages of 100 (the new `wholeCommits`, `wholeCompare`'s paging without its diff), and so do `report-outcome.mjs` `--find-prior` and `post-statuses.mjs` for a lane branch's commits. A page that does not read, or a list still shorter than `total_commits`, carries nothing and resumes nothing.
