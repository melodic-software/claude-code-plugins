---
bump: minor
---

### Changed

- Every step that updates a pull request branch now takes its method from one shared decision instead of a fixed merge rule. The decision returns no update, merge, rebase, delegate or hold from the branch's signals, `reference/branch-update-criteria.md` records the reasoning and sources per row, and the repository setting `pr_update_method` can force merge or rebase on the rows that allow it.
