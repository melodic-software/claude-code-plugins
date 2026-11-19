---
bump: minor
---

### Added

- `audit-derivability`, `audit-encapsulation`, `audit-noise`, `audit-progressive-disclosure`,
  `compress`, `extract-ssot` and `rename-references` accept the target-scope forms (`--repo`,
  `--repos-from`, `--owner`, `--fleet`, `--skip`, or the same request in words) and run once per
  repository. Each repository keeps its own settings, findings files, ledgers and pull requests.
  A run with no target form works as before.
- `reference/target-scope.md`, a generated copy of the target-scope contract, and a "Several
  repositories" section in `context/clean-tree-fallback.md` with the rules all seven skills share.
