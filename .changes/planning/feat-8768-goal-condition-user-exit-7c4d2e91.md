---
bump: minor
---

### Added

- **`/planning:draft-goal-condition` gives a condition that waits on the user a way to end.** When the intent has a step only the user can decide (a choice, a waiver, an approval, a change of plan), Step 2 ends the condition with an OR exit that names those items: each one still unmet is recorded in a named file as waiting on the user, with the exact reply or command they must give, and the file's contents are shown in the conversation. Step 2 also refuses, or rewrites with the user's agreement, a draft whose only end state needs a decision the user may make the other way, names an identifier the user can replace (a pull request number, an artifact or document URL), or fixes an order of work the user may reorder or defer.
