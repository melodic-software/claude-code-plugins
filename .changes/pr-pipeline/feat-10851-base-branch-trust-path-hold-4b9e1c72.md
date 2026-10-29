---
bump: minor
---

### Added

- A base-branch trust-path hold: `pr-require-checks-trust-paths.yml` runs ci-workflows' shared hold from `pull_request_target`, which posts a failing `ci-status` status when an agent App touched a pull request that changes a path in `.github/trust-path-hold.json`. `scripts/sync-hold-floor.py` generates that file from the same floor and `merge.trust-path-hold-apps` as the inline hold, which stays.
