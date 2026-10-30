---
bump: patch
---

### Fixed

- `pr-require-checks-trust-paths` no longer runs while the trust-path hold is off. Its success
  `ci-status` commit status met the required `ci-status` check before the ci-status check run
  started, so the merge queue could take an armed pull request's unchecked new head. It runs again
  when the repository variable `TRUST_PATH_HOLD` is `on`, the fourth step of restoring the App
  hold.
- `ci-status` no longer tries to turn off an armed pull request's auto-merge on a push: its token
  holds `contents: read` and the mutation could not succeed. The merge queue's check for a
  pr-verify pass at the exact head it merges is what holds a new head.
