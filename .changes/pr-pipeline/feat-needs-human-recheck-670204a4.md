---
bump: minor
---

### Added

- On its schedule, `pr-merge` takes off a `needs-human` label the lanes App set for a pr-unblock
  escalation once the recorded reason no longer holds at the head: `workflow-staged` when main
  changes nothing under `.github/workflows/` since its merge base with the head, `unresolved-conflict`
  and `protected-path-conflict` when GitHub reports the PR mergeable, `feedback-protected-path` when
  the PR changes nothing under `.github/`. It posts one comment naming the reason and the head first,
  never touches a label a person added, and keeps the label once a person commented or reviewed after
  the escalation. At most five a run. `version` stays 2.
