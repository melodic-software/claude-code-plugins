---
bump: patch
---

### Fixed

- `check-trusted-trigger` stops a pull request whose `base.ref` is not the payload's `repository.default_branch` with the new reason `untrusted-base`, on `pull_request`, `workflow_dispatch` and `workflow_run` alike, as it does a payload without the default branch. Before, a listed author's PR stacked on another branch passed. `report-check-run` maps `untrusted-base` to no skip reason, so the check posts failure, not neutral.
