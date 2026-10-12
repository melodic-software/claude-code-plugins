---
bump: minor
---

### Added

- babysit-prs: `babysit_merge_policy.py recheck --repo --pr --base-sha`, the merge-group backstop for a non-human enqueue. An entry whose merge-queue enqueue event has a human actor and enqueuer passes without reading any term; any other entry fails first on the effective rung and the kill switches, then on eligibility and its class against the rung, another agent-identity entry in the queue, a grouping other than ALLGREEN, the scorer's path and size terms, a body hold, a human blocking comment, or an opt-in label removed since enqueue. Exit 0 pass, 1 fail, 2 unreadable.
