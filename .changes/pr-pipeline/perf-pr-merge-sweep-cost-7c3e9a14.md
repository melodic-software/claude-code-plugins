---
bump: minor
---

### Added

- New config: `merge.max-queue-ejections` (default 2, 1 to 20). The unattended merge gate refuses to
  enqueue a head the merge queue has removed that many times for failed checks since the head last
  changed (a pushed commit or a force push), and posts one marked comment naming the failing
  `merge_group` runs; an unreadable timeline, or 20 items with no head change, also refuses.
  `version` stays 2.
