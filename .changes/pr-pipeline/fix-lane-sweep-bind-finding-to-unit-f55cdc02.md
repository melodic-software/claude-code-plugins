---
bump: patch
---

### Fixed

- The lane sweep's file step drops a finding whose slice is not its unit's, whose workflow is not its slice A or D unit's, or whose job is not among the jobs its unit's data lists, so a judge steered by CI log text cannot file a finding against a workflow or job its unit does not show.
