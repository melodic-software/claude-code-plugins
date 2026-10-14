---
bump: minor
---

### Added

- **`/session-flow:audit-sessions` sweep reports edit churn per linked PR (`edits.churn_per_pr`).** It sums each path's stored edits over the sessions that link exactly one PR and raises a `churn` finding, routed to `/session-flow:retro`, for every path within a PR edited more than this machine's threshold (5, the p90 of a 320-session spike). Each evidence entry names the PR's `repo` and `number`, the `path`, its `edits` and the `sessions` behind them, and the markdown report lists those sessions too. Paths stored as the `<suppressed>` or `<too-long>` placeholder are not counted. Sessions linking several PRs are left out, no PR review outcome is read, and records without `prs` or `edits` sweep as before; the store schema stays v1. A rule may now carry a `caveat`, listed under the report's Unchecked section.
