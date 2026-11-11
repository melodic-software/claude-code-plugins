---
bump: patch
---

### Changed

- `audit-coverage` and the `principles` reference files cite the "Coverage artifacts" rows of
  `reference/collectors.md` for lcov and coverage.py versions instead of restating them, and
  `principles` points at the shellmetrics README for shell-dependent values.
- `principles` now says the plugin has the `audit` skill and its `audit-*` siblings, names
  `audit-suppressions --findings` as the one findings file, and describes the mypy figure as a
  ratio over expressions. The c8 link in `audit-suppressions` points at the README section that
  exists. No behavior change.
