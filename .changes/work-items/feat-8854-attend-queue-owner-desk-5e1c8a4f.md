---
bump: minor
---

### Added

- **`attend-queue` lists `[held]` and `[post-merge]` rows.** A `[held]` row is an open pull request carrying the human-gated role label or `do-not-merge` that does not list as `[escalated]`, so no pull request lists twice. A `[post-merge]` row is an open human-gated issue whose first body line is a `babysit-merge-demotion` or `post-merge-failure` record marker, counted only from the workflow identity or a trusted escalation author; a record from anyone else is reported as a suspected spoof. Both rows only prompt the operator: the lane claims, edits, closes, reverts and merges nothing on them.

### Changed

- **`attend-queue`'s default order is owner-blocked pull requests (`[escalated]` pull requests, then `[held]`), then stopped work (`[ratify]`, then `[escalated]` issues), then `[post-merge]`, then `[intake]`,** oldest first within each row kind; the operator's chosen order still overrides it. Every row carries its link, and the skill states that issue-lane hand-backs arrive as `[escalated]` rows with their run link.
