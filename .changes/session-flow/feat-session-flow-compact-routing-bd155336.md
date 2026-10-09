---
bump: minor
---

### Changed

- `/session-flow:workflow`'s continuation router makes `/compact` the default within a phase or activity and lets it repeat; an already-compacted session no longer routes to a handoff for that reason.
- Switching to unrelated work hands off when anything carries over and plain `/clear`s when nothing does.
- Before suggesting `/compact`, `/clear` or a handoff, the router records every decision made and every pending decision with its recommendation in a durable file (the plan, spec or workflow checklist, also on a handoff route) and asks the pending ones while the user is present; a `/clear` with nothing to carry over records nothing.
