---
bump: minor
---

### Added

- `create` runs one quick check of the changed files before it pushes and opens the pull request (§2.3.4), skipped when prep's check passed on the same head: the repository's affected-files check without its tests, plus guardrails `reference-verify` and bash-format `lint-full` where the repository has them.

### Changed

- Prep's verify gate (§1.5) is that same quick check and runs no test suite; CI runs the suites, and `ready` runs them only on a head CI has not tested.
