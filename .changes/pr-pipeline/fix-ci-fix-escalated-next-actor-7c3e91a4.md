---
bump: patch
---

### Fixed

- A `ci-fix-escalated` stop now queues the pull request for a session builder, so it no longer
  has no next actor once the dispatcher's same-head retry is spent. The label goes on at each such
  stop while that retry still runs, and the session that finds the head green or lands the fix
  removes it; no lane removes it. `escalation-routes.json` gives the reason
  `"label": "needs-session"`, and `report-escalation.sh` adds that label, on a fail route only and
  only a well-formed label name, before the lane-stopped comment that names it. It puts the label
  back when a session removed it and the lane stops again on the same head.
