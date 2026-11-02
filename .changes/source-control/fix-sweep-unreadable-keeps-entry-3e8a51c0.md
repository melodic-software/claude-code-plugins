---
bump: patch
---

### Fixed

- `babysit-prs`: the pr-merge merge job's queued-entry sweep no longer dequeues an entry whose verifier verdict it could not read (`verify:unreadable`). The merge queue's own verdict reader refuses that entry fail-closed, so the sweep leaves it queued and does not count it as kept. When the merge job's whole artifact listing failed, the sweep used to remove lanes App entries that enable-auto-merge had just armed on a pass, and they cycled in and out of the queue.
