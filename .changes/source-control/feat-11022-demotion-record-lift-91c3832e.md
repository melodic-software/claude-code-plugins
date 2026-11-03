---
bump: minor
---

### Added

- `babysit_lift.py`: `canary-block` and `revert-block` print the lift block a canary or revert demotion record carries (per path, a 12-hex SHA-256 prefix and count for each line the merge deleted), and `close` closes each open canary, revert or read-back record that has lifted by the merge gate's own rule, removing its human-gated label.

### Changed

- The merge gate lifts a canary, revert or read-back demotion record on its own evidence (`babysit_merge_policy.py` `_lift`), as it already clears a red-main record once main is green. A record lifts when its own condition holds on main again (the content its lift block names is in main's tree again, beyond the copies the file still held at the record's own SHA; a read-back record's pull request reads back after all), or when a pull request that references it merges into main after it was filed, at a merge commit on main's history, the reference made no later than the merge by a person with write access or the agent identity, with that condition holding there (a canary record whose block says nothing was deleted needs a passing canary push run at that commit; a read-back record needs that pull request to read back; a revert record needs nothing more). A record a non-human edited, a failed read, or more than 100 references lifts nothing, and a canary record with no lift block still clears only on a person's close. The read-back and canary record bodies say how they lift.
