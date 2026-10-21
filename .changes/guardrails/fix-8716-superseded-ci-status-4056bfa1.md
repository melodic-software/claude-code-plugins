---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer reports a superseded contract-only `ci-status` as failing (#8716).** When a full run is in flight on the head, the contract-only `ci-status` run fails with the annotation `superseded by full run <url>/actions/runs/<id> in flight on <sha>`, and the guard counted that red run as `Failing checks: ci-status`. A failed run whose only failure annotations are that marker for the PR's head and the runner's `Process completed with exit code <n>.` line no longer counts: the named full run's `ci-status` decides, and until that run exists the check is pending, so an immediate merge waits and an auto-merge or merge-queue request goes ahead. Any other failure annotation, such as a contract step's own error, leaves the failure standing. The guard reads annotations only for failed check runs, three at most; a failed read leaves the failure standing.
