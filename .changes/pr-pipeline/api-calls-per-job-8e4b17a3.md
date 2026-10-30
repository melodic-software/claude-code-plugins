---
bump: minor
---

### Added

- The log-api-budget action has a `calls` output, `<name>-calls=N` for each named token, taken from
  its api-calls line: the job's own requests.
- These jobs now end with the log-api-budget step and name `API_BUDGET_TOKEN: github-token`, so each
  run carries an api-calls line:
  - pr-unblock.yml: the not-run jobs, `conflict-scan-refusal`, `fix-ci-unreported` and
    `report-stop-status`.
  - pr-review-hosted.yml and pr-review-security-hosted.yml: `resolve-model` and `kill-switch`.
  - pr-run-activity-read.yml: `broker-check`, `issue-fields`, `summary` and `report`.
  - pr-run-activity-write.yml: `report`.

### Changed

- pr-merge's sweep line reports the job's own request counts,
  `sweep-calls=N github-token-calls=M candidates=… reached=… skipped=…`, in place of
  `sweep-cost=… github-token-cost=…`. That was the rise in a counter every concurrent job shares,
  which the action documents as not the job's cost.
