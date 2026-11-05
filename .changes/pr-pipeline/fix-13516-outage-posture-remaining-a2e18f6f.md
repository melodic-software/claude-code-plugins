---
bump: patch
---

### Fixed

- `report-escalation` posts no lane-stopped comment when `report-stop-status` withholds the failing status for a workflow-modified token refusal the feedback sweep sends again
- Monitor signal 13 counts intake-triage's apply-verdict hold, read under its own per-lane cap, and the lane-holds run listing pages instead of dropping runs past the first 100
