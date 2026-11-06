---
bump: minor
---

### Changed

- CI `fix-docs` is on again: `limits.fix-docs-per-run` is `2`, for every pull request not tidied in its own run. A `work-resolve-issue` pull request tidied in its own run (within the tidy cutoffs) is skipped: the lanes App's on a lane branch whose file count, added plus removed lines, paths and areas are within `resolve-issue`'s `tidy.cutoffs`. One over any cutoff is dispatched, and so are the App's other pull requests and a person's on a branch with a lane name.
- pr-refine's plan job reads the base config through resolve-config's own loader, with its schema and file checks, instead of a `yq` conversion.
