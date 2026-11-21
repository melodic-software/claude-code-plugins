---
bump: patch
---

### Changed

- pr-unblock's address-feedback select counts a PR's earlier model rounds from one GraphQL query instead of one check-runs listing per commit, so the read no longer grows with the PR's commit count. A commit whose check suites or runs run past a page, or a PR past 100 commits, is still read over REST, so no round is missed.
