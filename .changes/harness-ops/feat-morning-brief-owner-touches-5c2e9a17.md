---
bump: minor
---

### Added

- `/harness-ops:morning-brief` prints an Owner touches section: per UTC day over the last `--touch-days` (default 2), the operator login's approvals, merges and `do-not-merge` lifts, the hold label (`--hold-label`, default `needs-human`) applied and lifted, and escalation comments; then hold waits from apply to lift, escalations by lane, kind and reason, and the most-touched items. It reads GitHub's own timeline events with one paged GraphQL search per day, so it needs no store and a later run compares against an earlier one. An escalation counts only from the lane identity (`merge.agent-identity` in `pr-pipeline.yaml`, or `--lane-identity`) or the operator (`gh api user`, or `--owner-login`). The operator login's actions include any agent session holding that login, and the section says so.

### Fixed

- The Stuck section's upstream pointers name the GraphQL reference pages that now hold the search query and the labeled event.
