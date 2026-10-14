---
bump: patch
---

### Fixed

- **`babysit_merge.py` enqueues on a merge-queue base through GraphQL `enqueuePullRequest`.** GitHub
  refused the REST `merge-async` call with `merge_action=merge_queue` for the lanes App
  ("Enqueuer is not authorized to merge"). The mutation pins the vetted head as `expectedHeadOid`
  and never sets `jump`. A refusal or an answer without a queue entry is held, with no other API
  tried and nothing recorded. A direct merge still uses `merge-async`.
