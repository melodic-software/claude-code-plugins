---
bump: patch
---

### Fixed

- The post-merge check no longer demotes unattended merging when a run listing answers without the dispatch runs it holds. Before a missing dispatch run becomes a failure, it reads the dispatch runs at the merge commit; a run there that the listing lacked, or a listing whose `total_count` exceeds what it returned, makes the verdict unreadable. The demotion filer reads the record listing again before filing, so a lagging listing no longer files a second record for one failure.
