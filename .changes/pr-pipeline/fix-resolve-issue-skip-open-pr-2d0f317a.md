---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer opens a second PR for an issue that another open PR already closes. A PR can gain its closing keyword while the model runs, after the `issue-prior` check read none, as happened with [#10698](https://github.com/melodic-software/claude-code-plugins/pull/10698) and [#10686](https://github.com/melodic-software/claude-code-plugins/pull/10686). `report-outcome` now reads the issue's open closing PRs again just before it opens a PR, applying the same trust rule as `issue-prior` (opened by the lanes App or a listed human). When one closes the issue, it opens no PR, logs that PR's number and stops `closed-by-open-pr`, a new `retry` route in `stop-routes.json`.
