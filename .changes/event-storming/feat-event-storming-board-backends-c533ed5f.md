---
bump: minor
---

### Added

- Boards sit behind named board operations (`reference/board-operations.md`) with two backends: markdown, the default, and Miro (`reference/board-backends/`). A run picks its backend from a `--backend markdown|miro` argument, then the board it is given (a Miro board URL or a `.md` path), then the new `board_backend` option, then markdown. When the chosen backend is not available the run stops and offers the routes; it never switches backends on its own.
- Markdown boards: one file per board under the team file's new `board_dir` key (default `docs/event-storming`), one folder per session. The skill writes them only through the tested `scripts/board-md.mjs` (`new`, `apply`, `check`, `parse`) and never commits them; people edit them by hand. Board text is escaped and never read back as structure.
- Only the facilitator writes to a board; persona agents read it and return their stickies as data.
- Eval cases `simulation-default-markdown` (renamed from `simulation-miro-absent`), `simulation-backend-miro-unavailable` and `simulation-evaluate-markdown-board`.

### Changed

- **Breaking:** enabling the `miro` plugin no longer puts runs on a Miro board. Set `board_backend` to `miro`, pass `--backend miro`, or give the run a Miro board URL to keep using Miro.
- **Breaking:** the plugin now needs Claude Code v2.1.271 or later, because the `board_backend` option limits its value with `options`; earlier versions cannot load the plugin.
- The Miro reference moves to `reference/board-backends/miro.md` and now holds every Miro tool name, color and coordinate; the skills name operations only.
- Run-state entries record each board as `{backend, ref}`; an older entry with a bare URL reads as a Miro board.
