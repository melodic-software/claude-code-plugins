---
bump: minor
---

### Changed

- address-feedback and fix-ci run the check-affected self-check over their uncommitted work before they hand it on, as resolve-issue does; the runner stages checks and self-checks under prepare: review-threads and ci-context.
