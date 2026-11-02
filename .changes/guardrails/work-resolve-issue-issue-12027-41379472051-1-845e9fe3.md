---
bump: patch
---

### Fixed

- `block-unresolved-pr-merge` no longer deadlocks a pull request that fixes a broken reusable workflow or action. When the PR changes a file under `.github/workflows/` or `.github/actions/`, or a root `action.yml` or `action.yaml`, a failing check that the base branch's rules don't require is reported as a warning and does not block. The required set comes from the branch's rulesets and its classic protection. A required failing check still blocks. If either read fails, or no check is required, every failing check blocks as before. Unresolved threads and change requests block in every case.
