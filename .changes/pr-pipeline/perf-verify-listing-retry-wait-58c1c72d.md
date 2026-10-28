---
bump: patch
---

### Changed

- The merge queue's cold-read headroom is 1,546 requests per queue entry (7,830 with the queue building 5), up from 1,520. It now counts the verdict reader's three incremental reads of at most 13 pages each, where it counted one, so a cold reader starts only with the headroom its listing caps can spend.
