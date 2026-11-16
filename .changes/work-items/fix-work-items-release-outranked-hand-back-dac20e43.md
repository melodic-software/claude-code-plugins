---
bump: patch
---

### Fixed

- The GitHub adapter's `release` of a live lease that an earlier live lease outranks backs off as `renew-lease` does before it exits `7`: it tries to supersede its own lease twice and hands the assignee back once one try succeeds, else keeps the assignee and says so. Before, it wrote nothing, so the lease and its login stayed until the TTL ran out.
- The assignee hand-back judges each lease list attempt at a clock read taken just before it. Before, it read the clock after the list, so a same-login lease renewed meanwhile could look expired and its holder was unassigned.
