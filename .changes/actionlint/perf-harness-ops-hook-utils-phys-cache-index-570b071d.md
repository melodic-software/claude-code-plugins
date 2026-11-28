---
bump: patch
---

### Changed

- The shared hook library's physical-path cache answers a lookup in the order its paths were primed from the next slot, and rules out an uncached path with one string match, so a plugins sync read no longer rescans the cache for every catalog entry; results are unchanged.
