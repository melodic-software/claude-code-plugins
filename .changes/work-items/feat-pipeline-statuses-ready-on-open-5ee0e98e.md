---
bump: minor
---

### Changed

- `/work-items:work --issue <n> --ci` runs the pull-request prep (a fresh-context review, build and tests, lint and the class audits) before it reports done, and records each in `work-outcome.json` as `steps`, which the CI lane posts as `pipeline/<step>` commit statuses. The lane now opens its PR ready.
