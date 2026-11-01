---
bump: minor
---

### Added

- `/harness-ops:morning-brief precision` reports the review-lane precision series for the pull requests merged in a closed UTC window: per lane (`claude-review`, `claude-security-review`) and per PR, the findings posted, each fresh finding's outcome (`valid-fixed`, `valid-follow-up`, `intentional`, `incorrect`, `uncertain`, `answered-unlabeled`, `unanswered`), reposts counted apart, precision beside the unlabeled and unanswered counts, and rounds to pass (`lane_review_rounds`, `fix_rounds`) against the pipeline's round cap. `--save-snapshot` and `--snapshot` split the fetch from a pure compute, so the same window gives the same bytes ([#7638](https://github.com/melodic-software/claude-code-plugins/issues/7638)).
