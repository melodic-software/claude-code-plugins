---
bump: patch
---

### Fixed

- `babysit-prs` no longer counts toward `merge.max-queue-ejections` a merge-queue removal caused
  by the merge group's `CI Status` failing on a GitHub rate limit alone, once that limit has
  reset, so an exhausted `GITHUB_TOKEN` pool no longer strands a head until a push. Any other
  failed-check removal, or one whose evidence cannot be read, counts as before.
