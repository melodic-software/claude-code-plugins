---
bump: patch
---

### Fixed

- `pr-unblock.yml` posts `pr-unblock / fix-ci` neutral `not-applicable` on the head when
  `fix-ci-context` skips (a closed pull request or no failing check). The skip posted no check,
  so `fix-ci-dispatch.mjs` sent the same lowest-numbered pull requests again on every run and
  starved every other red one.
