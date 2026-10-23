---
bump: patch
---

### Changed

- work-unblock's restart sweep reads a reopened fix issue's comments and events once: the recurrence check and the restart check share that read instead of listing both again, so each alert-filed issue costs one or two fewer lanes App calls per sweep, with the same verdicts.
