---
bump: patch
---

### Fixed

- A git-hook entry installed before its manifest listed an asset now reads `stale` rather than `modified` in `verify` and `plan`, so `copy` refreshes it and adds the asset without `--force`. Deleting an asset the install's stamp covers still reads `modified`.
