---
bump: patch
---

### Changed

- The work-unblock and intake-triage apply-verdict jobs log the lane token's and the job token's REST budget at mint and at job end (`.github/actions/log-api-budget`), as pr-merge does, so each run's lanes App spend is on record. pr-run-activity-write logs it at mint, before the head checkout replaces the base checkout the step runs from.
