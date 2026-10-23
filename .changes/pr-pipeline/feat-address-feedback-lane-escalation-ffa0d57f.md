---
bump: minor
---

### Changed

- `address-feedback` works a pull request carrying the human-gated label when a lane escalation (pr-unblock or fix-ci) put the label on and no review-lane hold names the current head or is open; a review-lane hold, or anything ambiguous, still limits it to threads a trusted person with write access asked it to fix. The label stays on for `clear-escalations` to remove.
