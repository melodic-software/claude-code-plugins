---
bump: minor
---

### Changed

- `babysit_merge.py`: a cancelled `merge_group` run no longer spends `merge.max-queue-ejections` ([#8566](https://github.com/melodic-software/claude-code-plugins/issues/8566)). GitHub records a removal after a cancelled run as a `failed_checks` removal too. Once the removals since the head changed reach the lower of the two caps, the gate reads the pull request's `merge_group` runs once and pairs each removal with the newest merge group created at or before it. A group with a `cancelled` run and no failed or unfinished one is a cancel, and cancels have their own cap of 2 (`babysit_merge_policy.MAX_QUEUE_CANCELS`). A removal no run pairs with, or runs that cannot be read, counts against the failure cap. `read_merge_queue` now reports each failed-check removal's time as `failedRemovals`. `queue_ejection_hold` now returns an `EjectionHold`, and `_merge_group_runs` replaces `_failed_merge_group_runs`. The unattended enqueue records `cancelledEjections`, and `babysit_verify_evidence.py evidence --lane-queue` reports it, so enable-auto-merge re-arms a lane pull request that a cancelled run removed. The refused-head comment counts both kinds of removal, and it lists the cancelled runs when any removal counted as a cancel.
