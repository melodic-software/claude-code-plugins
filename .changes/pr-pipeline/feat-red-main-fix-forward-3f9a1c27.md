---
bump: minor
---

### Changed

- The red-main report plans no revert when a guard fails (not the lanes App's merge, past `max-culprit-age-hours`, itself a revert, already decided, over `daily-cap`, a suspected platform fault, or a revert that does not apply): the post-merge fix issues fix `main` forward through the issue lane, and no draft revert labeled `needs-human` is planned for a person. The report's decision for that case is `fix-forward`; the log still reads `human` in older reports as the same decision. The guards are unchanged.
