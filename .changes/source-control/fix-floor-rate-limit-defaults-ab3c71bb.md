---
bump: patch
---

### Changed

- `babysit_gh.py` reads its `limits.api` defaults (`writer-pause`, `read-floor`, and github-token's `limit-cap`, which replaces the `GITHUB_TOKEN_LIMIT_CAP` constant) from `.github/actions/log-api-budget/rate-limits.json` instead of the pipeline schema, with the same values. A missing or invalid file still refuses every call, and a default that is not a number now does too.
- `babysit_risk.HIGH_FLOOR` also holds `.github/actions/log-api-budget/rate-limits.json`, the rate-limit defaults `rate-guard.mjs` reads, so a change to one waits for a person.
