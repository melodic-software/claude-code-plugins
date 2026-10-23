---
bump: patch
---

### Changed

- A branch- or head-scoped workflow-run listing that reaches GitHub's 1,000-run search cap (by `total_count` or by the runs its pages carried) is now an incomplete read, never a complete one. In `collect_lane_runs` it raises, so the unattended merge gate binds no lane (`evidence-missing`) and holds the pull request. In the post-merge check it makes the verdict unreadable (exit 3), so pr-merge holds and files no record; before, a listing past the cap read as complete with a `listing-capped` warning. `babysit_gh` gains `RUN_SEARCH_CAP` and `run_search_capped`.
