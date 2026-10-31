---
bump: patch
---

### Changed

- **`pr-merge-dispatched-*` artifacts now expire after 30 days instead of 90.** The post-merge check reads these records only back to its floor, and its run listing goes unreadable at 1000 dispatch runs, about 19 days at the current rate, so the rest of the 90 days was dead weight: over half of the repository's artifacts, paid for on every full listing. The other 11 days cover a stopped check. A record that expires early fails closed: it can hold the lane or demote, never verify a merge. Artifacts already uploaded keep their 90-day expiry.
