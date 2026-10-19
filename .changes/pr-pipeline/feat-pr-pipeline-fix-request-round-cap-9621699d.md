---
bump: minor
---

### Changed

- At the address-feedback round cap (`loop.review-rounds`), a kept thread with a fix request
  from a write-access trusted person created after the newest counted round (its latest round
  marker or model check-run completion) runs one more round, on the requested threads only; other
  kept threads wait, and without such a request the PR still escalates `feedback-round-cap`. A
  round with no readable time grants none
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).
