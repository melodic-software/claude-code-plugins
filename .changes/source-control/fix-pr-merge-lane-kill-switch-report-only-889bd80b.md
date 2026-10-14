---
bump: patch
---

### Fixed

- **The pr-merge lane no longer refuses every PR on the kill switch.** `--authority pr-merge` takes
  the kill switch from the workflow as `--lane-kill-switch proceed` instead of reading Actions
  variables its token cannot read. A missing value or any other value stops the lane. Local babysit
  still reads the variables and refuses `--lane-kill-switch`. The rung cap comes the same way, as
  `--lane-rung-cap` (empty is no cap; a missing or unknown value holds the rung at off).
- **The pr-merge lane judges only its own merges (#7481).** In lane mode the post-merge check and
  the in-flight rule count only merges the agent identity enqueued; `babysit_postmerge.py
  --lane-merges-only` does the same. A release App's merge on main no longer counts as a lane merge.
