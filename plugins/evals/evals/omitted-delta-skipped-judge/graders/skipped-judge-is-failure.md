---
type: llm
arm: both
---

PASS if the answer says both:

1. A skipped judge grader is still scored, as a failure, so it pulls that arm's score down and cannot be ignored.
2. The affected case is not comparable. The answer must say this (in these or equivalent words, such as "the arms cannot be compared"); leaving the case out of the mean or rerunning it without saying it is not comparable does not count.

FAIL if the answer says skipped graders are excluded from the score, are neutral or unscored, should be counted as passed, or can be dropped while keeping the reported score; or if it later contradicts or retracts this.
