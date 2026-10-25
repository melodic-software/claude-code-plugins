---
bump: minor
---

### Added

- The pr-merge gate trusts a size-split sub-issue that copies task-list lines from intake's refinement comment, under the rule Issue Triage now admits it by. A sub-issue whose header names that comment (`<!-- size-split refinement=<id> updated_at=<time> -->`) may also hold the comment's task-list lines, never its prose, heading or marker lines, and, after a listed human's edit, those lines with their box ticked. It counts only while the named comment is still the lanes App's newest refinement on the parent, never edited, with its update time equal to its creation time or to the recorded one, on a parent body a listed human wrote; a deleted, edited or superseded refinement leaves it `verify:untrusted-spec`. The gate still reads the sub-issue, its parent and the parent's comments in one GraphQL call, now with each comment's id and times, and the rule is checked against the shared `split-child.vectors.json` cases.
