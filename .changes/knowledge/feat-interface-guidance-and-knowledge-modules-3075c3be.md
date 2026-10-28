---
bump: minor
---

### Added

- `scripts/work-root.mjs` resolves the work root every knowledge skill writes under: the session's git top-level (the working directory outside git) joined with `library_dir`, expanding `~` and `${NAME}` / `%NAME%` and failing on an unset variable. `--progress-key` prints the distill progress key. `reference/work-root.md` states the rule once.

### Changed

- `/knowledge:docpage-digest`, `/knowledge:map-corpus`, `/knowledge:video-digest`, `/knowledge:course-digest` and `/knowledge:distill` resolve their roots through `work-root.mjs` instead of `CLAUDE_PROJECT_DIR`. In a worktree session, video-digest's default work root and distill's target skill directory and progress key are now that worktree's own; a main checkout keeps its existing progress key.
- `/knowledge:course-digest` keeps its course layout, `courses/<platform>/<slug>/`, now under the work root; with no `library_dir` set it lands under the session's git top-level instead of the plugin data directory.
- `/knowledge:course-digest` no longer requires Claude in Chrome: Phase 1 discovery and the adapter discovery checklist use the browser tool the `/testing:run-e2e` browser-tool rubric picks, the Playwright CLI by default.
