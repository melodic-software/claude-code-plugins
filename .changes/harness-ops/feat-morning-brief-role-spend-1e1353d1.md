---
bump: minor
---

### Added

- `/harness-ops:morning-brief` prints a `SPEND:` line in the Lanes section for each credential role whose API-key legs it read, from the lane-outcome records' `costUsd` (the CLI's list-price estimate, not billing): a per-day estimate from the median cost of the role's successful key legs, credit stops left out, times the runs of the lanes those legs ran in, with the number of key legs read and their sum. Subscription-token legs are left out, and a role whose key legs carry no cost prints `cost not recorded`. It makes no new API calls.
