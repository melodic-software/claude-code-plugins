---
bump: patch
---

### Changed

- design's grading hygiene gate records its items without a confirm-before-finishing step

  The items the criteria doc records are unchanged. A new eval case,
  design-grading-hygiene-recorded, checks that the doc names a grader
  model other than the one under test and states the re-run cost.
