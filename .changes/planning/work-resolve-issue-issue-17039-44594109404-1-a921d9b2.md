---
bump: patch
---

### Fixed

- **The six `plan-reviewer-cut-medium-*` eval cases can pass on the shipped plan skill.** Their
  `reviewer-not-dispatched` grader no longer sets `max: 0`, because under `auto` a MEDIUM blast
  radius runs the plan reviewer, so the grader could not pass in the same run as
  `blast-radius-medium`. A reviewer dispatch is now a must-pass sample. The `low-*` cases still
  require no reviewer dispatch.
