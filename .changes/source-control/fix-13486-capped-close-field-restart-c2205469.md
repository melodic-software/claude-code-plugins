---
bump: patch
---

### Changed

- In a repository whose pipeline file sets `models.issue-status`, a capped close writes no `agent-ready` label. A fresh attempt clears the issue's Work status field and sets it to `agent-ready`, as the issue lane's restart does, in place of taking `agent-ready` off and putting it back; a set that GitHub does not keep fails before the pull request closes. A parked issue, and one held at the cap, no longer has `agent-ready` removed. A rerun after a failed close restarts nothing when the lanes App already set the field to `agent-ready` at or after its record, or when a person has since moved the field to another state, and treats a park as done once the field reads `confirmed`, whatever labels remain. A repository without `models.issue-status` keeps the label writes it had.
