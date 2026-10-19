---
bump: patch
---

### Changed

- `/session-flow:orchestrate worker` and `worker compact` exports now carry a one-line rule against ending the turn to wait on the worker's own background job: poll in the foreground with a bounded loop, or return what you have.
