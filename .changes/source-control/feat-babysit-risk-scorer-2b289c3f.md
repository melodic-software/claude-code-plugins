---
bump: minor
---

### Added

- `babysit_risk.py`, the diff risk scorer for the unattended merge path: a pure function that rates a pull request LOW, MED or HIGH from its work class, size (the changed-line limit from `merge.diff-check.max-changed-lines`, and 8 files), a case-insensitive HIGH path floor joined with `merge.diff-check.denied-paths`, and the review-lane evidence, with sorted reason codes. A path outside the tracked-path character set, or any malformed input, rates MED or HIGH. Nothing calls it yet.
