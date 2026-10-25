---
bump: minor
---

### Added

- Intake's size split also copies, as written, the task-list lines of intake's refinement comment on an issue a listed human filed, where admission already counts that comment as spec. A Size Large issue whose done-when lives only in that refinement no longer stays parked with no one asked. Each sub-issue that copies a refinement line names that comment's id and update time in its header.
- Admission and pr-verify trust such a sub-issue only while the named comment is still intake's newest refinement on the parent, never edited, with its update time equal to its creation time or to the recorded one, and only on a parent body a listed human wrote. Every line must be one of the listed human's task-list lines or one of that comment's task-list lines, never its prose; after a listed human's edit, either kind may also have its box ticked, and nothing else. A deleted, edited or superseded refinement makes the sub-issue untrusted, even when a listed human has edited it since.
