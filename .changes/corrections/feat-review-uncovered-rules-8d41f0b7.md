---
bump: minor
---

### Added

- `/corrections:codify reviews` lists each `Uncovered rule:` line a CI review lane recorded in its summary as a candidate rule beside the mined lessons, read by a parser that keeps only lines inside the lane's `Uncovered rules (N)` block of a post by the lane bot ending in its `claude-lane:` footer, and returns their text as data. A candidate still goes through the threshold, the old-versus-new proof and a person's approval.
