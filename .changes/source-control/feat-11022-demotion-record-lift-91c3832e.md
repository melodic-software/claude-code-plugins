---
bump: minor
---

### Changed

- The merge gate lifts a `revert` or `read-back` demotion record on its own evidence, as it already clears a red-main record once main is green (`babysit_merge_policy.py` `_lifted_at`). Either record lifts once a pull request that references it merges into main after it was filed, at a merge commit on main's history; for a read-back record that pull request must also read back (the agent identity's newest pin comment is unedited, was posted no later than the merge, and names the head that merged). A read-back record also lifts when the pull request it names reads back by that test after all. A record a non-human edited, a failed read, or more than 100 references lifts nothing, and a canary record still clears only on a person's close. The read-back record body now says how it lifts.
