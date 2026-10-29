---
bump: patch
---

### Fixed

- A `work-resolve-issue` reuse PR whose runner check failed no longer carries `Hold: a human merges
  this` or the `human-merge-hold` label. A failed check is not a reason for a person: the PR opens,
  its Verification section lists the failure, and `ci-status` reruns the check on the head, where
  the fix lanes take it. A `done` run with a failed runner check still opens no PR and retries
  (`check-failed`). `merge: human`, untrusted provenance, an unreadable denied-path or changed-file
  list, path holds and a reuse leak scan that is not `clean` still hold (`mustHold` in
  `report-outcome.mjs`).
