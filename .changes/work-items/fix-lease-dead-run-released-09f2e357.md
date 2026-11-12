---
bump: patch
---

### Fixed

- The github tracker's `claim` treats an earlier live lease held by a completed workflow run
  (`session_id` `run-<id>`) as released: one run read, the lease superseded in place, and the
  claim holds, so a lane run that died before its release no longer blocks the issue's re-fire
  until the lease's TTL. A live run, any other `session_id`, or an unreadable run status still
  wins arbitration.
