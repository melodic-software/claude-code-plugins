---
bump: patch
---

### Fixed

- The pr-merge lane's queue sweep and capped close now hold on a member's newest comment saying "do not merge", the rule its arm path and gate apply. A wider read dequeued an entry the next run armed again.
