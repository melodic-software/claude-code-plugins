---
bump: patch
---

### Fixed

- The shared session server reads and drops a request body it refused unread (a body over its cap, a chunk it already holds) after sending the answer, until the client closes, the declared length is read or two seconds pass, before it closes the connection. Closing with the body unread reset the connection, and a client still sending its body got the reset instead of the 413.
- The tunnel watch can no longer allow a switched-from address again after its grace time ended: two syncs of the tunnel record no longer overlap, so one that read the record before the grace ended cannot apply it over a later one.
