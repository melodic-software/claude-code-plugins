---
bump: patch
---

### Changed

- The merge gate's `evidence-unbound:<lane>` hold with the reason `rerun-not-allowed` now names
  the fix: start a fresh App-triggered head with `gh pr update-branch <n>`, never a hand
  `gh run rerun` of an App-started lane run, which puts attempt 2 on the owner login. The GitHub
  provider's babysit-prs safety reference states when a lane run's second attempt binds and when to
  update the branch instead.
