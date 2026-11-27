---
bump: patch
---

`babysit_postmerge.py` reads a pull request whose newest lanes App pin record is a `babysit-merge-unpin` comment as unpinned, matching the merge queue's pin hold, instead of falling back to the older pin.
