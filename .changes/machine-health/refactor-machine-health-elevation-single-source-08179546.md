---
bump: patch
---

### Changed

- The pre-run elevation banner's "Covered non-elevated" list now names every enabled check that runs without admin, read from the catalog, instead of a fixed list that had fallen behind; `reference/windows/elevation-matrix.md` points to `Get-ElevationMatrix.ps1` instead of keeping its own copy of the table.
