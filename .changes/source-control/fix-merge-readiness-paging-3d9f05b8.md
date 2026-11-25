---
bump: patch
---

### Fixed

- The pull-request skill's merge preflight (`merge-readiness.sh`) reads every page of a pull request's reviews, check runs and commit statuses (and of the changed files, branch rules, annotations and pr-verify artifacts it reads), not only the first 100 ([#18954](https://github.com/melodic-software/claude-code-plugins/issues/18954)). A change request in a later review, or a failed or pending check past the first 100, now holds the merge, and a list longer than 20 pages is `UNCHECKED`.
