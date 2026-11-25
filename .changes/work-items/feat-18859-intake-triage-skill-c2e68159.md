---
bump: minor
---

### Added

- `/work-items:triage --issue <n> --ci`: an intake lane mode that writes `triage-verdict.json` (labels, comment, needs_human, size, complexity, uncertainty, flags, blocked_by) for the lane to apply, with no tracker writes of its own, and `scripts/check-ci-verdict.mjs`, which checks that the comment opens with the five verdict lines its fields give.
