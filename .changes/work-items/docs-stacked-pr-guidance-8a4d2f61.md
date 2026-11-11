---
bump: patch
---

### Changed

- `reference/execution-shape.md` adds "Stacked per-item PRs": a chain of items that each build on the one before can ship as a stack under `per-item PRs`, deciding by the source-control plugin's `reference/stacked-prs.md`. `decompose`, `ship run` and `work` point at it; `work` states that CI mode never stacks.
