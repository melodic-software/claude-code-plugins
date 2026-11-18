---
bump: minor
---

### Added

- Every item `/improvement:find` files, attended or unattended, carries the `source: improvement-find` label. The skill never creates the label: when it is missing, an unattended run files nothing and records a gap, and an attended run shows the command that creates it.
- Unattended filing has a hard stop: while the open items carrying that label number at or above `find_open_item_cap` (a new key in `.claude/improvement.md`, default 5), the run files nothing and says so, and below it the run files no more than the room left. The invocation prompt cannot raise it; the per-run adaptive cap stays as it was.

### Changed

- The search-before-create step is stated as a pre-filter that skips an obvious repeat. Intake triage decides whether a filed item is a duplicate.
