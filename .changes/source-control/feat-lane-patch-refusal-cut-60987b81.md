---
bump: minor
---

### Changed

- `pull-request comments --ci` and `ci --ci` keep away from `.github/workflows/` only, not all of `.github/`. The review-thread tool, `feedback-thread.sh`, refuses a path under `.github/workflows/` in any letter case and allows a kept thread's path elsewhere under `.github/`.
