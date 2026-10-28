---
bump: patch
---

### Changed

- The review callers' `hold-paths`, ci-status's exempt-author `hold_patterns` and merge-holds.mjs `HOLD_PATH_CLASSES` and `COST_PATHS` are generated from `babysit_risk.FLOOR_CLASSES` and `COST_PATHS` by `scripts/sync-hold-floor.py` (`--check` fails on a stale copy); the floor holds the generator as `gate`.

### Fixed

- ci-status's exempt-author check matches the trust-gate paths case-insensitively, as the floor does elsewhere, so a Dependabot, release App or standards-sync pull request that changes `.github/codeowners` or `vendor/.GitModules` fails for a person instead of passing.
