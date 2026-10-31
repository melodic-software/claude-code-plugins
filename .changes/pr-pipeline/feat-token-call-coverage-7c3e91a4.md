---
bump: minor
---

### Added

- `mark-lanes`, `lint-repo`, `lint-shell`, `check-plugins` and `check-skills` now report their job
  token requests: `gh` runs through the api-budget wrapper in their steps, in the hygiene aggregator
  and in the Dependabot signature check, and each job ends with `api-budget` and `api-calls` notices.
  zizmor's online audits spend the token through their own client and stay uncounted.

### Changed

- `api_budget_emit` prints the last reading of each resource and reset, so a notice shows each core
  counter a job touched, not only the one its last call landed on. The job's latest core reading
  stays the last line.
