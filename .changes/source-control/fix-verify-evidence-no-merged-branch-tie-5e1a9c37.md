---
bump: patch
---

### Fixed

- The pr-merge verifier gate no longer holds a pull request with `verify:earlier-fail` for a FAIL that ties to it only by head branch when the pull request that FAIL judged is merged or closed, so a new release pull request on the reused `release/plugins` branch stops inheriting the FAILs of earlier, merged release pull requests. A FAIL from an open pull request on the same branch, or one whose state cannot be read, still holds.
