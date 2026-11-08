---
bump: minor
---

### Added

- The babysit scripts read the Work status hold and ready states from `models.issue-status` in `pr-pipeline.yaml`. `hold-states` lists the states that hold a linked issue (default: `needs-human`, `needs-owner-decision`, `needs-reporter-info` and `needs-spec`). `ready-state` names the state a fresh attempt restarts at, which a bot-setters value never counts for (default: `agent-ready`).
- The verifier's capped close restarts an issue with the tracker binding's admission label, the `autonomous-eligible` role in `config.role_labels` (default: `agent-ready`), as the merge gate already reads it.
