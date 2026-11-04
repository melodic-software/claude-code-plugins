---
bump: patch
---

### Changed

- Eval case `t4-apply-migrate` no longer grades the removal of `.claude/developer-experience.md`. The eval sandbox denies that removal because `.claude/` is a protected path, and the validity gate fails a run on the denial, so the prompt now keeps the old file and the `old-file-removed` grader is dropped ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
