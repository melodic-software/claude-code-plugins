---
bump: patch
---

### Changed

- `merge.max-queue-ejections` no longer counts a merge-queue removal whose merge-group run failed
  only `CI Status` on a GitHub rate limit, once that limit has reset; a removal whose evidence
  cannot be read still counts.
