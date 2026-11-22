---
bump: minor
---

### Changed

- `/testing:run-e2e` reads `recording` and `browser_mode` from `<home>/testing/e2e.md` and its personal override `<home>/testing/e2e.local.md`, and the worst-case catalog extension from `<home>/testing/worst-case.md`, `<home>` being the convention home (`docs/conventions` by default). The old `.claude/testing/e2e.md`, `.claude/testing/e2e.local.md`, `~/.claude/testing/e2e.md` and `.claude/testing/worst-case.md` are still read where no `<home>` file supplies that layer, and each run prints one warning per old file naming where to move it ([#18051](https://github.com/melodic-software/claude-code-plugins/issues/18051)).
