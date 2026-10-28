---
bump: minor
---

### Added

- `limits.readmit-per-run` in `pr-pipeline.yaml` (default 20, at most 100): how many open `status: ready` issues with neither `agent-ready` nor `admission-deferred` one work-unblock sweep runs intake's admission rules on. An issue left out before the rules run does not count.

### Fixed

- work-unblock's hourly sweep now runs intake's admission (`admit.mjs` `decide`) on open `status: ready` issues that carry neither `agent-ready` nor `admission-deferred`, such as a deferral whose label was lost or a `status: ready` set by hand. Before, nothing revisited them. One listing per sweep, oldest updated first. An issue with a hold or refuse label, an open blocker or an open sub-issue is left out unread; one whose `status: ready` neither a listed human nor the lanes App added, or whose `agent-ready` removal still stands, is skipped after its events are read. The writes match intake's: `agent-ready` within the queued cap's room, `admission-deferred` past it or while an open pull request is for the issue, and a refusal parked at `status: confirmed`, or at `status: needs-decision` when it holds for a person.
