---
bump: minor
---

### Added

- `/review:merge-risk`: rates one pull request's merge risk against one rubric (alignment with the closing issue, impact, verification, reversibility, error detection), each `LOW` to `CRITICAL`, checked blind by a fresh-context agent, with a `demote` flag that may only send an unattended merge to a human. A one-way door rates `HIGH` on its own, so no area averages it down.

### Changed

- `/review:explain-change` takes its risk map from `/review:merge-risk` and drops `--risk-only`; a request for the risk rating alone goes to `/review:merge-risk`.
