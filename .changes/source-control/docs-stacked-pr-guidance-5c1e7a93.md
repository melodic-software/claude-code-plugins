---
bump: patch
---

### Changed

- The stacked pull request reference moves to the plugin level, `reference/stacked-prs.md`, so other plugins can point at it. Its "When to stack" section is now the one place that says when to stack: dependent changes, a large change split for review, and ordered series stack; independent changes stay separate PRs off the trunk. It also says to check that the repository's PR pipeline accepts a layer whose base is not the default branch before stacking, replacing the stale line that said the pipeline lanes skip such a layer.
- `pull-request` asks the stack-or-separate question before `create` opens a PR that builds on another open PR, and `worktree` create points a stacked layer at the layer below it.
