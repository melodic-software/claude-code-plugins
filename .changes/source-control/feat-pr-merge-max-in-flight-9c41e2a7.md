---
bump: minor
---

### Added

- `merge.max-in-flight` (default 1) sets how many lane merges the unattended merge gate allows in flight: the agent identity's merge-queue entries plus its merged pull requests the post-merge check has not verified. `in_flight` refuses at the cap with the reason of the entry or merge that reached it, and refuses on an unknown enqueuer, an unreadable queue or a truncated history under any cap. After an enqueue, the entry dequeues itself when the identity's earlier entries plus the unverified merges already fill the cap. The post-merge check still charges every unverified merge whose commit a red run contains, so a breakage found with several in flight fails the check and files a demotion record for each.
