---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer resumes an earlier run's lane branch that is behind the default branch. Such a branch carried its stale base into the runner's whole-branch checks, which failed and handed the issue to a person with no pull request. The run now starts fresh from the default branch under a new lane branch and leaves the old one in place. `issue-prior` reads `behind_by` from the compare call it already makes, and fails the step when that value is not a whole number. The outcome comments say a restart continues from the branch only while it is not behind.
