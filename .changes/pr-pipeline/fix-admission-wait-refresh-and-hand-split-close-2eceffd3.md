---
bump: patch
---

### Fixed

- A Size Large issue whose sub-issues are all closed but which is still open is refused at admission (`status: confirmed`) instead of parked as "split pending" on every hourly sweep. work-unblock now closes finished split parents before it re-runs admission, so a parent whose last sub-issue just closed is closed rather than refused.
- A split parent's admission comment no longer keeps saying the split is pending once sub-issues exist. When a sub-issue closes, work-unblock rewrites that comment to name the open sub-issues. The hourly sweep also rewrites it for one twenty-fourth of the waiting parents, chosen by issue number, so each is checked once a day.
- A parent split by hand now closes as completed once its sub-issues are done, when each unticked task-list item in its body cites one of its sub-issues as `#N`. An uncited item still keeps it open.
