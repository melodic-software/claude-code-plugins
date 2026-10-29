---
bump: minor
---

### Added

- pr-merge's scheduled `clear-escalations` removes a human-gated label a review lane added when every hold comment since the label was last removed names an earlier head, as `stale-review-hold`. At the current head it needs a trusted move (every push since the one that landed the newest held head is by a `human` of the base trusted-actor list, never the lanes App), both review lanes passed (each caller's newest run's status job succeeded with a review-complete notice and no hold notice for the head, on a head that changes neither review caller), and no HIGH or CRITICAL security finding: a whole security review, every finding inline, `critical-findings: 0`, and no unresolved security-lane thread at `CRITICAL` or `IMPORTANT` (or with no readable severity). A lane that still finds the cause holds the new head again. `ci-status`'s review-lane lift check accepts that removal only when the lanes App made it directly, after its own `stale-review-hold` comment since the hold naming a head no hold comment names.
