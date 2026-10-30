---
bump: patch
---

### Fixed

- `review-venue.sh` takes a workflow run listing page only when its `workflow_runs` holds every run
  its `total_count` leaves for that page. It reads an incomplete page up to three times. When the
  page is still incomplete, each lane it leaves undecided reads `local unreadable` and runs its
  review locally. A short or partial page no longer reads as `absent` or `stale`.
