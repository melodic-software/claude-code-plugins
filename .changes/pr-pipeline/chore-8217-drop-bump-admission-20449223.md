---
bump: patch
---

### Changed

- "Dependabot pull requests" and the review-dependency activity no longer list the `[dependabot skip]` version-bump commit as an allowed commit: every commit must be Dependabot's or, after a review, the lanes App's fix commit, and a `github-actions[bot]` push is refused (`pushed-by:github-actions[bot]`).
