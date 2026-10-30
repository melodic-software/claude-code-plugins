---
bump: minor
---

### Changed

- Intake admission refuses an issue whose body has a line opening with `Hold:`, and holds it at `status: needs-decision` for a person.
- Intake admission admits a lanes App issue only as a trusted size-split sub-issue (`splitChildBody`). Any other issue the App filed holds at `status: needs-decision` for a listed human to file as their own, even when a listed human's comment carries the criteria.
- Intake admission under a room claims the issue's place with a fresh `admission-deferred` before it adds `agent-ready`. It adds `agent-ready` only while fewer issues than the room count ahead of it: issues the issues listing shows with either label, placed by their newest claim (else first `agent-ready` add) since 10 minutes before its status read, with a tie or an unread add counted ahead. Parallel apply-verdict runs for different issues no longer each take the same room. A loser, or a run whose read fails, stays deferred for work-unblock's sweep.
- intake-reenter no longer removes `needs-human`: a decision on an issue that carries it changes nothing. A listed human's removal of `needs-human` now re-enters an issue at `status: needs-decision` as well as one with no `status:` label.
