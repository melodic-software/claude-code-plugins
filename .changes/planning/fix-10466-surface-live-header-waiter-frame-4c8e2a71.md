---
bump: patch
---

### Fixed

- The surface-ui-c phase 6 Live check no longer flakes on loaded runners: it asserts the header reads
  Live only once the page server counts the waiter, and checks the released state only once the
  server reports reading with no lease and no waiter. A server test covers the state frame a waiter
  arriving or leaving pushes while the lease is held.
