---
bump: patch
---

### Fixed

- The merge gate's cost-decision carry (`babysit_merge_policy._carries`) reads a compare whose unpaged commit list stops short of `total_commits` again in pages of 100 (`_whole_commits`), as `merge-holds.mjs` does, so a range of more than 250 commits carries. A page that does not read, or a list still shorter than `total_commits`, carries nothing.
