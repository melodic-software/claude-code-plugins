---
bump: major
---

### Added

- `linkage_gate_uses_pattern`, in `docs/conventions/source-control.yaml` or as a userConfig option (the YAML wins): the POSIX ERE a `.github/workflows` file must match for the PR-body linkage hooks (`pr-body-linkage-gate`, `pr-linkage-mcp-gate`) to run in a repository.
- `runner_policy_paths`, `org_settings_repo` and `review_lane_producer_repo` in `docs/conventions/source-control.yaml`: where `/source-control:babysit-prs` routes a wrong runner label, an organization-settings finding, and a review-lane check name that does not match the gate's.

### Changed

- The PR-body linkage hooks no longer carry a built-in workflow path: with `linkage_gate_uses_pattern` unset they gate no repository. To keep the earlier scope, set it to `\.github/actions/pr-require-checks/(check-contract|report-ci-status)([@[:space:]]|$)`.
- The babysit-prs routing text and the pull-request watch hand-off no longer name a specific organization's repositories or tools.
