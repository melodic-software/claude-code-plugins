---
bump: minor
---

### Added

- pr-merge's scheduled `clear-escalations` removes a human-gated label a review lane added when every hold comment since the label was last removed names an earlier head, as `stale-review-hold`. At the current head it needs a trusted move (every push since the one that landed the newest held head is by a `human` of the base trusted-actor list, never the lanes App), a whole review from both lanes that passed (each caller's newest run's status job succeeded with a review-complete notice and no hold notice for the head, on a head that changes neither review caller), and no HIGH or CRITICAL finding: `critical-findings: 0` from the security lane, every finding inline for the security lane and any lane a hold names, and no unresolved lane thread at `CRITICAL` or `IMPORTANT` (for those strict lanes, none with no readable severity either). It reads the head and the hold comments again just before the removal. A lane that still finds the cause holds the new head again.
- `ci-status`'s review-lane lift check counts the lanes App's removal only after its own `stale-review-hold` comment since the hold names a head no hold comment names, while no hold comment names the event's head, and only when the base commit's `clear-escalations.mjs` `recheckStaleHold`, the same predicate, passes again at that head with the job's own token. The App's comment only points at the hold; ci-status does not take its judgment on trust.
