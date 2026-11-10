---
bump: patch
---

### Fixed

- Monitor signal 13 (lane holds) no longer goes unread for every lane when one lane has more unread runs than its cap, or the read span falls short of the window. Such a read is partly read: a lane whose read runs reach the threshold still files or keeps the incident, and only a whole read clears it.
