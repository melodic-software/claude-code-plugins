---
bump: minor
---

### Changed

- At the address-feedback round cap (`loop.review-rounds`), a pull request whose open findings all come from the code review lane no longer goes to a person. One more round runs on every kept thread, a fresh fixer in a new session like every round, and the round marker names it as past the cap. After that round the select job skips `cost-gated`, adds no label, and waits for the next write-access fix request. A security lane finding, a pr-verify note (an intent mismatch) or a `claude[bot]` finding, whose lane no footer proves, still escalates `feedback-round-cap`, before and after the fresh fixer's round.
