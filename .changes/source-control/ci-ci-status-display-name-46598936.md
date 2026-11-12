---
bump: patch
---

### Changed

- `babysit-prs` reads the gate as `CI Status`, else `ci-status` on a head tested before the
  rename: the Dependabot class's gate read, the post-merge check (CI Status and its `ci-status`
  alias count as one check) and the verifier's draft-run read (CI Status's job, never the alias's).
