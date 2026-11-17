---
bump: patch
---

### Changed

- The GitHub tracker's `claim`, given `--session-id run-<id>` with `GITHUB_SERVER_URL` set, adds a readable link to that workflow run below the lease marker, so the issue lane's claim comment shows which run holds the issue. Lease reads are unchanged.
