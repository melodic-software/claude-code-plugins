---
bump: patch
---

### Fixed

- work-resolve-issue's `post-statuses.mjs` posts a resumed branch's `pipeline/*` statuses only while the branch ref still points at the tip run-checks checked; a branch that moved, or whose ref cannot be read, gets no status, as report-outcome already treats those check results.
