---
bump: patch
---

### Fixed

- The interview page's header now shows Live as soon as a watcher starts waiting, and drops it when
  the wait ends, even while the lease stays held: the page server pushes a state frame whenever a
  waiter arrives or leaves, where before such a frame came only with some other change.
