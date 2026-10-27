---
bump: patch
---

### Changed

- The pr-merge hold-path floor moves `.github/workflows/pr-merge.yml` and `.github/workflows/pr-require-checks.yml` from the `gate` class to `enforcement` (owner direction 2026-10-27): a pull request that changes them clears on a clean security review bound to its head instead of waiting for a person, once that review can bind. Today it cannot: both files grant write scopes and `pr-merge.yml` also runs on `pull_request_target`, so each stays a lane source (`babysit_review_evidence.readonly_workflow`) and an edit to either still waits for a person. `trust`, the pr-merge scripts, `docs/conventions/pr-pipeline.yaml` and `babysit_merge*` stay in `gate`. `babysit_risk.FLOOR_CLASSES` and `merge-holds.mjs` `HOLD_PATH_CLASSES` change together.
