---
bump: patch
---

### Changed

- tidy-diff drops the closing read and second read from the residue pass

  The residue pass already sweeps every kind in order, so the reads after
  it re-checked the same list. Opus 5 checks its own work without being
  told to.
