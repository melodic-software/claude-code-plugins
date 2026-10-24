---
bump: patch
---

### Fixed

- The lane sweep's file step drops a finding whose slice is not its unit's, whose workflow is not its slice A or D unit's, or whose job is not among the jobs its unit's data lists, so a judge steered by CI log text cannot put a finding in the digest against a workflow or job its unit does not show. A unit that lists no jobs leaves the job unbound; the free-text signature still lets a steered judge mint fresh fingerprints, which land only as digest entries, at most 3 per unit.
