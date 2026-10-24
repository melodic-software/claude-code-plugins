---
bump: minor
---

### Changed

- At the address-feedback round cap (`loop.review-rounds`), a pull request whose open findings all come from the code review lane gets one fresh fixer round, a new session like every round, before it goes to a person. That is the last automatic round: once it has run, no sweep, schedule or dispatch starts another, and the PR escalates `feedback-not-converging`, with a comment that gives the round count and names each open review thread. A write-access fix request still gets its own round. A security lane finding, a pr-verify note (an intent mismatch), a `claude[bot]` finding, whose lane no footer proves, or a pull request a person gated with the human-gated label (its hold lifts only on a fix request newer than the last round) still escalates `feedback-round-cap` at the cap.
- The address-feedback round marker reads `round <N> of max <M>`, M being the cap plus the fresh fixer's round, and a round-cap escalation's neutral `address-feedback` and `publish-feedback` checks add the same line to their summary through `report-check-run`'s new `not-run-detail` input, which shows only that line.
