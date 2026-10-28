---
bump: patch
---

### Changed

- The merge gate's path floor (`babysit_risk.FLOOR_CLASSES`) holds `.github/scripts/pr-unblock/fix-ci-context.mjs` and `.github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs` as `enforcement` paths, since `clear-escalations.mjs` now loads them: a change to either waits for a clean security review bound to the head.
