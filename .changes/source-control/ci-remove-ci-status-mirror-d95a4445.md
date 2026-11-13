---
bump: patch
---

### Fixed

- `pull-request` merge after AI review accepts a base ruleset that requires `CI Status`, the renamed gate check, as well as one that still requires `ci-status`; it stopped with "base ruleset does not require ci-status" once the org ruleset moved to `CI Status`.
