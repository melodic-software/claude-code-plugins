---
bump: minor
---

### Added

- Three `recall-*` eval cases rebuilt from bugs the review lanes missed (#8254, #7617 and #5997),
  each with a regex grader that reports the bug found or missed at its file and line in the
  rebuilt files.
- The README asks a pull request that changes a review lane's prompt, model or effort to cite the
  recall score before and after the change.
