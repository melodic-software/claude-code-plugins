---
bump: minor
---

### Added

- `babysit_risk.py`, the diff risk scorer for the unattended merge path: a pure function that rates a pull request LOW, MED or HIGH from its work class, size (200 changed lines, 8 files), a case-insensitive HIGH path floor joined with `merge.diff-check.denied-paths`, and the review-lane evidence, with sorted reason codes. Nothing calls it yet.

### Fixed

- rate odd path forms HIGH in the risk scorer

  Mark a path unsafe when it has a `..` segment, a trailing `/`, a `:` in a
  segment (NTFS stream) or a `~<digit>` segment (8.3 short name), and reject
  configured denied-path globs that name no path ('', '.', './').
