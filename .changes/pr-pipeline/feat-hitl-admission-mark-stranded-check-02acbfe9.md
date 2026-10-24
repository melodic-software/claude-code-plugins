---
bump: minor
---

### Added

- A listed human adding `admission-deferred` to a decided issue with `status: ready` now has the hourly work-unblock sweep run intake's admission rules on its own work-class label and Size, Complexity and Uncertainty fields, each counting only when a listed human or the lanes App added or set it, admitting it when there is room and refusing it to `status: needs-decision` with a comment otherwise.
- The sweep now re-fires an `agent-ready` issue left with no run and no report for 3 hours, once per version of the lane workflow files, and then hands it to a person with `needs-human` and a comment.

### Changed

- Intake admission now reads the `- [ ]` acceptance criteria only from text a listed human wrote, in the body or a comment of their own, since pr-verify judges a lane pull request only against that text (owner decision Q9). The lanes App's refinement comment no longer satisfies the criteria check; a person who confirms it posts the criteria as their own comment.
- Intake admission now refuses an issue with more than 100 comments, since pr-verify reads only the first 100 and stops on such an issue.
