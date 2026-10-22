---
bump: minor
---

### Changed

- `merge.diff-check.high-path-floor` is `false` in this repository (owner decision Q681): a lane
  pull request touching the fixed HIGH path set, `floor-paths`, `floor-script-scopes` or capability
  frontmatter no longer waits for a human. The verifier verdict, both AI review lanes, `ci-status`
  and the post-merge revert breaker still gate it, and the cost hold is unchanged.
