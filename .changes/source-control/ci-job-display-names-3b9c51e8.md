---
bump: patch
---

### Changed

- `babysit-prs` reads the claude-code-plugins jobs by their Title Case check names (`PR Review /
  review-status`, `Kill Switch`, `Test Bash (3)`), else by the job id on a head tested before the
  rename or in a repository whose jobs have no display name; post-merge baselines compare a check
  across both forms. `pull-request` review-venue finds `Test *` lanes too.
