---
bump: patch
---

### Changed

- `/review:quality-gate` `spec` and `close-out` modes read the item body through `/work-items:track view`, and close-out derives each sub-item's merged PRs through `/work-items:track changes` and `/source-control:pull-request view`, with the open-PR search through `/source-control:pull-request list --search`. The skill no longer grants `gh issue view`, `gh pr list` or `gh api graphql`.
