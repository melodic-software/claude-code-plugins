---
bump: minor
---

### Added

- `babysit_risk.py`, the diff risk scorer for the unattended merge path: a pure function that rates a pull request LOW, MED or HIGH from its work class, size (200 changed lines, 8 files), a case-insensitive HIGH path floor joined with `merge.diff-check.denied-paths`, and the review-lane evidence, with sorted reason codes. Nothing calls it yet.
