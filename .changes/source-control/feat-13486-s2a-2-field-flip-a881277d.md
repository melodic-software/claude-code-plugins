---
bump: patch
---

### Changed

- In a repository whose pipeline file sets `models.issue-status`, the capped close now reads an issue's status as the Work status field decides it: a status label for another queue state gives way to the field, while hold labels and `agent-ready` stay. A parked issue whose field reads `confirmed` counts as done even if a stale `status: ready` label is still on it.
