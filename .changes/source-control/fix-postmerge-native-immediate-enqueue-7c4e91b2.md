---
bump: patch
---

### Fixed

- The post-merge check counts a lanes App merge as native when arming an already mergeable pull request enqueued it at once, so GitHub recorded no auto-merge event. It counts the merge only when every enqueue on the pull request is the identity's and `merge.lane-prs` was `native` at the merge commit's parent. Such a merge no longer waits on a pin the gate never posts, and no longer turns into a false read-back demotion after six hours. A human enqueue, `merge.lane-prs: gate`, or an unreadable config keeps the pin read-back. The babysit-prs safety reference describes this rule, the pin `enable-auto-merge` now posts before it arms, and the residual.
