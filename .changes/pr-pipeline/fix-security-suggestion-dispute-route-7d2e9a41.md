---
bump: patch
---

### Fixed

- A disputed security-review finding rated `SUGGESTION` no longer hands the pull request to a
  person. address-feedback reads the finding's one `severity:` line (`severityOf` in
  `address-feedback.mjs`) and holds for a person only at `IMPORTANT` or above, the rating this
  repository counts as HIGH (`SECURITY_PERSON_SEVERITY`). A `SUGGESTION` is adjudicated as a
  code-review finding is, and an adjudicator's `security` question on it ends the lane in a failing
  status as `feedback-unadjudicated`, not `feedback-question-security`. Past the round cap it gets
  the fresh fixer's round. An `IMPORTANT` or `CRITICAL` finding, one with no rating, an unknown one
  or two that differ, and a thread a person directed still go to a person as before.
