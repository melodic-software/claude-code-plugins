---
bump: patch
---

### Changed

- The convention names the renamed intake, maintenance and post-merge jobs by their verb-first
  ids, among them intake-triage's `check-born-triaged` and `dispatch-refined-triage`, the lane
  audit's `assess-units` legs and `collect-key-handoffs`, the tidy lane's `select-areas` and
  `sweep-areas` legs, the mutation run's `check-range`, `check-key-credit` and `run-mutants`, and
  the changelog lane's `select-release`, `apply-changelog` and `verify-env-scrub` legs. Each job's
  display name is its id in Title Case. `key-job` inputs, markers and artifact names not built
  from a job id are unchanged.
