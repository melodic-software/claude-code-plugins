---
bump: minor
---

### Added

- A Node step that sets `API_BUDGET_SCRIPT` ends with its own api-calls notice,
  `::notice title=api-calls::script=<name> github-token=N lanes-app=N not-modified=M graphql=K`, counted
  from the readings the rate guard appends for the job-end notice, so a job's total splits by step.
  pr-merge's enable-auto-merge job names its eight counting steps (who, superseded, head-ref-map,
  listing-carry, carry-run-cache, verify-answers, lane-records, enable-auto-merge). No request
  changes.
