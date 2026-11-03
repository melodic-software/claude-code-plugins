---
bump: patch
---

### Changed

- `pull-request`: `reference/create.md` is now an index of one file per section (`create-preflight.md` through `create-pushed.md`), and `reference/monitor.md` keeps its two checklists plus an index, with sections 3.0 through 3.5 in their own `monitor-*.md` files. The text is unchanged; pointers that cite a section (`SKILL.md`, `babysit-prs`, `config-resolution.md`, sibling references) now link its file, so a read returns that section instead of the whole reference.
- `pull-request` evals: `pull-request-monitor-arms-watch` checks the §3.0.1 Monitor watch (deadline maximum, a poll over all three review surfaces; the run needs `--allow-tools Monitor`), and `pull-request-create-pushed-names-head` checks that `create --pushed` names the head branch and never pushes again.
