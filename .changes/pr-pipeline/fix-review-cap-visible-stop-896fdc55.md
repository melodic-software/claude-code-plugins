---
bump: minor
---

### Changed

- Past the address-feedback round bound (`loop.review-rounds` plus the one fresh fixer round), a pull request whose open findings all come from the code review lane no longer skips `cost-gated` and waits with no label. It escalates `feedback-not-converging` with the human-gated label and a comment that gives the round count and names each open review thread. No sweep, schedule or dispatch starts another automatic round; a write-access fix request still gets its own round, and a security or intent finding or a pull request a person gated still escalates `feedback-round-cap` (`.github/scripts/pr-unblock/address-feedback.mjs`, `.github/scripts/pr-unblock/report-escalation.sh`).
- The address-feedback round marker reads `round <N> of max <M>`, M being the cap plus the fresh fixer's round, and a round-cap escalation's neutral `address-feedback` and `publish-feedback` checks add the same line to their summary through `report-check-run`'s new `not-run-detail` input, which shows only that line.
