---
bump: minor
---

### Changed

- `publish-promotion-evidence.mjs` emits a `re-earned` event for a cell once its existing predicate passes over only the merges after the latest contrary event against it or a prerequisite, a demotion record's creation among them. `since` is that instant rounded up to a whole second, as the merge gate's `--window-start` is, so a re-earn counted from the newest demotion record lifts the resolver's restart. `--out` carries forward a published re-earn the next run no longer derives, and still refuses to drop a contrary event.
