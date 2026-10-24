---
bump: patch
---

### Fixed

- `fix-ci` dispatch trusts a `ci-lanes` commit status by its creator's type and id (the GitHub Actions bot, `Bot` 41898282) instead of the login `github-actions[bot]`, which GraphQL never returns (it reports `github-actions`); no pull request was dispatched while the login check stood. A status set by any other actor, or with no creator, is still ignored.
- The dispatcher logs why it skips a listed pull request whose `ci-lanes` status failed or errored, so a skip of that kind is no longer silent.
