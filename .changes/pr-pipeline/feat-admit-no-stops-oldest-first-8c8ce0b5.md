---
bump: minor
---

### Changed

- Intake admission now treats a blocker closed as not planned or a duplicate as no longer blocking, and reads another repository's blocker there instead of waiting on it for good. Either still needs a close by a listed human or a merge.
- Intake admission takes the unblocked issues oldest first: an issue that passes the rules while an older open issue waits in `admission-deferred` is deferred behind it, and the hourly sweep admits them in order.
- The admission refusal comment no longer asks a person to add `agent-ready` by hand; it names what admission needs.
