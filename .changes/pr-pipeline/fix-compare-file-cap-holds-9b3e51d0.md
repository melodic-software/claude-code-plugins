---
bump: patch
---

### Fixed

- pr-merge's cost-decision lane vetting, `clear-escalations` (its lane-run check and `workflow-staged`) and `refire-refused` no longer fail closed on a compare that lists 300 files or more: past that cap they compare the paths they check (the review-lane workflows, the lane-token broker's files, `.github/workflows`) by git object at the merge base and the far end, and still hold when either listing cannot be read.
