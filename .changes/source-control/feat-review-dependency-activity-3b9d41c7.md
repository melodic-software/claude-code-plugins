---
bump: minor
---

### Added

- `/source-control:pull-request dependency --ci`, the pr-unblock lane's unattended review of one risky Dependabot update (a major bump, an action publisher outside the allowlist, a group holding a major, or a red `ci-status`). It reads the runner's context file, the checkout and the upstream release notes as data, may push a scoped fix outside `.github/` with `[dependabot skip]`, and returns a `merge`, `fix`, `close` or `escalate` verdict as structured output for a job with no model to act on. See `reference/dependency-ci.md`.
