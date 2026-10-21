---
bump: patch
---

### Fixed

- `babysit-prs` unattended merge: a default branch head that names a different `merge.agent-identity` now returns the `authority-differs` stop, and one whose pipeline config cannot be parsed (including a duplicate key) returns the `default-branch-unreadable` stop, so the identity's queued entries leave the merge queue instead of the run refusing and leaving them queued.
