---
bump: minor
---

### Added

- **The post-merge check counts the pr-merge lane's full-run dispatch.** A `pr-require-checks`
  dispatch by `github-actions[bot]` counts as the identity's when a run of
  `.github/workflows/pr-merge.yml` on the branch (not a `pull_request_target` run) uploaded the
  artifact `pr-merge-dispatched-<run id>`. A dispatch by another workflow, branch or actor still
  does not.
