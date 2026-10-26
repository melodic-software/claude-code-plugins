---
bump: patch
---

### Fixed

- Lifting the lanes kill switch no longer leaves open lanes App pull requests red until a push or a manual re-run. The next `maintenance-reconcile-lost-runs` run re-runs the failed `ci-status` of each lanes App pull request whose newest checks run failed, on its first attempt, only because the switch was on, recorded so `pr-verify` trusts the re-run, at most three per run. While the switch is on, the reconciler still reads nothing.
