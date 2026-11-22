---
bump: minor
---

### Added

- `create` runs one quick check of the changed files before it pushes and opens the pull request (§2.3.4), skipped when prep's check passed on the same head: the repository's affected-files check without its tests, plus guardrails `reference-verify` and bash-format `lint-full` where the repository has them.

### Changed

- Prep's verify gate (§1.5) is that same quick check and runs no test suite; CI runs the suites, and `ready` runs them only on a head CI has not tested.
- Prep's class table sends a `code` branch to the §1.5 changed-files check instead of `verification:confirm`, which ran the test suites.
- The babysit merge policy's carry refusals list `plugins/guardrails/git-hooks/reference-verify.sh` and `plugins/bash-format/git-hooks/lint-full.sh`, which CI now runs, so a push that changes either stops an approval carrying.
