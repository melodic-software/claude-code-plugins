---
bump: patch
---

### Fixed

- The post-merge check no longer judges an unsettled auto-merge that merged 30 days or more ago
  (`LANE_DISPATCH_RETENTION`, the retention-days of pr-merge.yml's `pr-merge-dispatched-<id>`
  uploads). Its dispatch record may have expired, so the verdict reads unreadable, naming the
  merge, rather than judging the merge on a record that may be gone; no run of it is read and no
  full run is asked for. A merge carrying the identity's settled marker stays verified at any
  age, and every merge younger than the retention is judged exactly as before.
