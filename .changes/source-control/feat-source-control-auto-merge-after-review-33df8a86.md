---
bump: minor
---

### Changed

- `pull-request` arms GitHub auto-merge without asking only after the AI review checks finish on the head commit, pinned with `--match-head-commit`, with no strategy flag behind a merge queue, and only in the 17 melodic-software repositories whose ruleset requires `ci-status`. A PR that changes CI workflows, permission or agent-instruction configuration still merges only when the user names it. It never passes `--admin`, `--merge` or `--rebase`. The monitor phase no longer says it never auto-merges.
