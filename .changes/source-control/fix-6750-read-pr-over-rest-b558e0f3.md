---
bump: patch
---

### Fixed

- `/source-control:pull-request view` reads the pull request, its files, and its diff through the REST API instead of `gh pr view` and `gh pr diff`, so `/review:explain-change` and the other callers get pull-request facts in sessions that refuse GraphQL, such as Claude Code cloud sessions. The facts keep the same fields and value shapes. `<pr>` may also be a head branch, and `--repo` takes `HOST/OWNER/REPO`.
