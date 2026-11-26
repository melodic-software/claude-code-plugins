---
bump: patch
---

### Fixed

- ci-status's cost-hold step vets a lane run on a head past the compare API's 300 files by the review-lane workflows' blobs at the merge base and the head (merge-holds.mjs `laneChangeListed`) instead of keeping the hold at "changes too many files".
