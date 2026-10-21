---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer reports a superseded contract-only `ci-status` as failing (#8716).** When a full run is in flight on the head, the contract-only `ci-status` run fails with the annotation `superseded by full run <url>/actions/runs/<id> in flight on <sha>`, and the guard counted that red run as `Failing checks: ci-status`. A failed run carrying that annotation for the PR's head no longer counts: the named full run's `ci-status` decides, and until that run exists the check is pending, so an immediate merge waits and an auto-merge or merge-queue request goes ahead. The guard reads annotations only for failed check runs, three at most; a failed read leaves the failure standing.

- keep a contract failure beside a superseded marker

  The merge guard took a failed contract-only ci-status run as superseded by
  the full run whenever it carried the superseded annotation, even when the
  run's own contract check also failed. The marker now counts only when every
  failure annotation is the marker or the runner's exit-code line.
