---
bump: patch
---

### Changed

- The babysit risk gate holds `.github/actions/log-api-budget/rate-guard.mjs` on its HIGH floor, since `check-trusted-trigger.mjs`, already on the floor, sends every GitHub call through it.
