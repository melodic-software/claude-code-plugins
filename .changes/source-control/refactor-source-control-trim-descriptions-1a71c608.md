---
bump: patch
---

### Changed

- Backfilled invocation probe sets (`probes/*.json`) for `/source-control:babysit-loop`, `/source-control:babysit-prs`, `/source-control:commit`, `/source-control:pull-request`, and `/source-control:worktree`, and trimmed all 6 skill frontmatter descriptions (4,262 -> 1,821 chars, -2,441c / -57.3%: `babysit-loop` 708 -> 331, `babysit-prs` 685 -> 322, `commit` 710 -> 345, `pull-request` 767 -> 350, `worktree` 705 -> 347, `setup` 687 -> 126) with zero body changes and zero probe trigger-rate regressions.
