---
bump: patch
---

### Fixed

- The merge guard reads every page of a pull request's reviews, check runs and commit statuses (and of the changed files, branch rules, annotations and pr-verify artifacts it reads), not only the first 100 ([#18954](https://github.com/melodic-software/claude-code-plugins/issues/18954)). A change request in a later review, or a failed or pending check past the first 100, now blocks the merge. A list longer than 20 pages lets the merge run with the "will run unchecked" notice, as the review-thread read already did past 2,000 threads.
