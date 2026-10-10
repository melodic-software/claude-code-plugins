---
bump: minor
---

### Added

- **Won't-do blockers.** The triage attention view has a fourth bucket, "blocked by won't-do": open items whose `blocked_by_wont_do_count` is above zero, whatever labels they carry, reported for the operator to drop the edge, re-scope, or close. The triage board accepts it as a `state`. The Jira adapter now reads done blockers' resolutions in one extra search and counts a blocker resolved as one of `config.jira.wont_do_resolutions` (team binding key, default `["Won't Do","Duplicate"]`, `[]` turns it off) in `blocked_by_count` and `blocked_by_wont_do_count`; a failed lookup keeps the done blocker blocking, as the GitHub adapter does.
