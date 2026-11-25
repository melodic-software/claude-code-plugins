---
bump: patch
---

### Fixed

- `resolve-config` no longer sizes an activity whose `applied-by` names `triage-verdict` by the issue's Size, Complexity and Uncertainty fields. Intake's `triage-issue` sets those fields, so it read them for a turn budget it does not use, and on its `workflow_dispatch` run, which carries no issue event, it failed with "an applies-when predicate needs fieldValues, which this run did not supply". A Large issue is triaged too, no longer skipped as `split`.
