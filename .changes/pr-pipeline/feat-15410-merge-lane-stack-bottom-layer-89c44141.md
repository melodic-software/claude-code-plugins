---
bump: minor
---

### Added

- The merge lane lands the bottom layer of a native GitHub stack whose stack base is `main` (owner decision on #15410, option B). GitHub refuses native auto-merge for every stack member, so where `enable-auto-merge.mjs` would arm such a layer it sends the asynchronous merge instead, pinned to the head it read, into main's merge queue when there is one, and only once the newest `CI Status` run at that head passed and every hold the arm checks is clear. A layer with an open layer below it is never merged, so no lower layer lands without its own holds checked. A merge GitHub refuses leaves the layer unmerged with a refusal comment for a person; the lane adds no credential. Into a merge queue GitHub refuses the lanes App's async merge today ("Enqueuer is not authorized to merge"), so there the layer goes to a person.
- The pin comment posted before a stack layer's async merge says the merge path is about to ask GitHub to merge it and that GitHub can still refuse it, instead of saying it is about to arm native auto-merge. The pin's first line is unchanged.
