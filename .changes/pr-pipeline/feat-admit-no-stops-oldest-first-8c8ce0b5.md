---
bump: minor
---

### Changed

- Intake admission now treats a blocker closed as not planned or a duplicate as no longer blocking, and reads another repository's blocker there instead of waiting on it for good. A blocker here still needs a close by a listed human or a merge; another repository's blocker counts only on a listed human's close.
- Intake admission takes the unblocked issues oldest first: an issue that passes the rules while an older open issue waits in `admission-deferred` is deferred behind it, and the hourly sweep admits them in order. While the sweep still counts only completed or merged blockers in this repository, an issue that rests on any other blocker never gets `admission-deferred`, which the sweep would drop without admitting it: with room it is admitted without that wait, and with the lane full it waits with a comment.
- The admission refusal comment no longer asks a person to add `agent-ready` by hand; it names what admission needs.
- An issue admission would refuse only for Size Large (split at intake pending, owner Q93) is parked instead: it keeps `status: ready`, gets no `status: needs-decision`, loses `admission-deferred` and gets a comment naming what it waits on. Any other refusal reason still refuses and names both.
