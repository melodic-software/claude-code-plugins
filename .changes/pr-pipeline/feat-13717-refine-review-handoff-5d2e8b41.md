---
bump: minor
---

### Changed

- CI `fix-docs` is on again: `limits.fix-docs-per-run` is `2`, for every pull request not tidied in its own run. A `work-resolve-issue` pull request, the lanes App's on a lane branch, is skipped, since that lane tidies its change in its run; the App's other pull requests, and a person's on a branch with a lane name, are not.
