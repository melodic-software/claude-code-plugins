---
bump: minor
---
### Added

- The babysit merge gate now re-runs an AI review check whose run an outage lost (`cancelled` or `timed_out`), at once and once per run on the pinned live head. A lost run whose lane already reached its side effect is left to a person: its job carries the lane's completion record, or the lane's reviewed-head marker or another lane comment appeared after the run started. The review evidence binds the second attempt by the same rule, also checking the lane's review threads (#8524).
