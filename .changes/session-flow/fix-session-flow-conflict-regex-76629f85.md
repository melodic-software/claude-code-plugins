---
bump: patch
---

### Fixed

- audit-sessions: the merge-conflict command match now runs in linear time on a long run of git global options, so a crafted transcript command can no longer stall the scan.
