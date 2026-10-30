---
bump: patch
---

### Fixed

- A `ci-fix-escalated` stop now hands the pull request to a session builder instead of leaving it
  with no next actor once its same-head retry is spent. `escalation-routes.json` gives the reason
  `"label": "needs-session"`, and `report-escalation.sh` adds that label, on a fail route only and
  only a well-formed label name, before the lane-stopped comment that names it. It puts the label
  back when a session removed it and the lane stops again on the same head.
