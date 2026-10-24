---
bump: minor
---

### Changed

- Intake admission now treats a blocker closed as not planned or a duplicate as no longer blocking, and reads another repository's blocker there instead of waiting on it for good. Either still needs a close by a listed human or a merge.
- Intake admission takes the unblocked issues oldest first: an issue that passes the rules while an older open issue waits in `admission-deferred` is deferred behind it, and the hourly sweep admits them in order.
- The admission refusal comment no longer asks a person to add `agent-ready` by hand; it names what admission needs.
- An issue admission would refuse only for Size Large (split at intake pending, owner Q93) or only because its acceptance criteria are in the lanes App's refinement on a human-filed issue (owner Q78 pending) is parked instead: it keeps `status: ready`, gets no `status: needs-decision`, loses `admission-deferred` and gets a comment naming what it waits on. Any other refusal reason still refuses and names both.
