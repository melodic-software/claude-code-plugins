---
bump: patch
---

### Fixed

- Every CI `npm ci` on a GitHub-hosted runner reads npm's fetch bound from one file, `.github/npm-fetch.npmrc` (fetch-timeout 60000, fetch-retries 1, below npm's 300000 and 2): `pr-require-checks.yml` names it as npm's global config at workflow level, which covers each `run-tests.sh` install, and each other workflow's installing job names it at job level from its own checkout. A stalled registry request now gives up after two 1-minute attempts and a retry wait of at most a minute, where it could hold a job for three 5-minute attempts. `resolve-config`'s own install in `action.yml` is unchanged.
