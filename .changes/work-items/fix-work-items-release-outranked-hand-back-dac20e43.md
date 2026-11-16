---
bump: patch
---

### Fixed

- The GitHub adapter's `release` of a live lease that an earlier live lease outranks supersedes its own lease and hands the assignee back before it exits `7`. Before, it wrote nothing, so the lease and its login stayed until the TTL ran out.
- The assignee hand-back judges each lease list at a clock read taken before that list. Before, it read the clock after the list, so a same-login lease renewed meanwhile could look expired and its holder was unassigned.
