---
bump: minor
---

### Added

- `/work-items:triage sweep` re-checks open issues already wearing the human-gated role label. It selects those that fail the label test and carry a `RECOMMENDED` line (from the seam's write identity or a user with write access) or an unedited `**Decision recorded.**` comment from such a user, and states the count before any change. Attended, it asks once for that count, then posts one comment per item carrying a `Decision defaulted` line, its basis and the failed test, and removes the label. Unattended, it reports the count and changes nothing. It skips pull requests, unclassed and human-floor items, signal-marked and escalated items, items the issue dimensions human-gated, and items a person re-labeled after an earlier sweep, and it applies no other label.
- `/work-items:attend-queue` lists parked human-gated issues and pull requests (the label with no trusted escalation marker) as `[human-gated]` rows after every other worked row, and works them one at a time in the same interview shape as escalations.

### Changed

- `/work-items:triage` states one human-gated label test: the label applies only when an item needs an irreversible act, a person's consent (a manual QA or UX sign-off included), a secret, or a design choice the owner has not made. A reversible change with a well-grounded recommendation takes the decision-defaulted exit instead, and the human-gated outcome in step 5 names which part of the test the item meets.
