---
bump: minor
---

### Changed

- `publish-promotion-evidence.mjs` emits a `re-earned` event for a cell once its existing predicate passes over only the merges after the latest contrary event against it or a prerequisite, a demotion record's creation among them. `since` is that instant rounded up to a whole second, as the merge gate's `--window-start` is, so a re-earn counted from the newest demotion record lifts the resolver's restart. Each contrary event carries `discovered`, the run that first published it, and the window starts at the later of each event's `at` and `discovered`, so a contrary event found after a re-earn restarts the window at that run whatever its date. An event published before `discovered` existed is stamped once with that file's `generated_at`. `--out` refuses any other change, addition or removal of a published event's `discovered`, and refuses a run whose clock is behind the previous publish. `--out` carries forward a published re-earn the next run no longer derives, and still refuses to drop a contrary event.
