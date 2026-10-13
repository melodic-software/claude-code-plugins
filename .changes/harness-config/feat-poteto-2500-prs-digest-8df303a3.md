---
bump: patch
---

### Changed

- **`/harness-config:audit-automation-gaps` reads the enforcement hierarchy from the shared enforcement ladder.** The skill carries a generated copy of the enforcement-ladder convention at `context/enforcement-ladder.md` and points at it instead of listing the levels inline. The ladder adds a `make-impossible` rung above compiler settings and a `canonical-helper` rung below the linters. A consuming repository's own order in its project instructions still overrides the default.

### Fixed

- **`scripts/fetch-docs.sh` runs its address check and interpreter probe with `python -I`**, so a module planted in the working directory (an `ipaddress.py`, say) is never imported by the `--public-only` check.
