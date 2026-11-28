---
bump: patch
---

### Changed

- Backfilled invocation probe sets (`probes/*.json`) for `/source-control:babysit-loop`, `/source-control:babysit-prs`, `/source-control:commit`, `/source-control:pull-request`, and `/source-control:worktree`, and trimmed all 6 skill frontmatter descriptions (4,262 -> 1,871 chars, -2,391c / -56.1%: `babysit-loop` 708 -> 303, `babysit-prs` 685 -> 348, `commit` 710 -> 345, `pull-request` 767 -> 408, `worktree` 705 -> 341, `setup` 687 -> 126) with zero body changes and zero probe trigger-rate or false-positive regressions.
