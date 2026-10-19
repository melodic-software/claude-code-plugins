---
bump: patch
---

### Changed

- A pull request that changes this convention adds a changelog fragment under `.changes/pr-pipeline/`
  (`scripts/new-changelog-fragment.sh pr-pipeline <bump>`) instead of a `CHANGELOG.md` entry, and the
  release pull request writes the fragments into one entry, so concurrent lane pull requests stop
  conflicting on this file. `version` stays 2.
