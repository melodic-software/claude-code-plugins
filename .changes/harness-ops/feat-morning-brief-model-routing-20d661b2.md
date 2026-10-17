---
bump: minor
---

### Added

- `/harness-ops:morning-brief`'s Lanes section gains a model-usage table, a baseline before model routing changes anything: per activity and profile over the runs that carry a lane record, runs, passes, median turns, max-turns hits and the models the lane records name (`models=`), with no sizes or costs. A pipeline lane's activity comes from its job's name in the jobs read the section already makes; the profile is the record's `profile=`, else `unknown`. New flag `--max-turns-hits N`: a row whose max-turns hits exceed it gets a `RECOMMENDED` line; unset by default, and the table then says no threshold is set.
