---
bump: patch
---

### Fixed

- `clear-escalations.mjs` lifts a stale review-lane hold when an unresolved review thread is at
  IMPORTANT: only a CRITICAL thread, or a strict lane's thread with no one readable `severity:`
  line, keeps the hold, as the merge gate already reads a review finding. A high path refused by
  pr-merge's risk score gets the lanes' comment and no `needs-human` label (owner decision
  2026-10-30, #11020). The README's `stale-review-hold` row and its lists of the reasons only a
  person clears say so.
