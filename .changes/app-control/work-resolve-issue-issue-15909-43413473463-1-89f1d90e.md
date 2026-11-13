---
bump: patch
---

### Changed

- `/app-control:map create` writes each feature's Drive steps with the action, the exact command
  or handle, and the observable result after `Result:`, ending in a `**Proof.**` step with the end
  state and its `Captures:`. It writes a result only from what discovery read or the app showed.
- `/app-control:map refresh` treats a Drive step with no `Result:`, a stated result the step did
  not show while the feature still worked, and a missing or stale proof step as doc drift, and
  corrects each from what the live pass observed. The source wave asks about them, and a legacy
  conversion adds the results and proof step with its `driven` marks.
