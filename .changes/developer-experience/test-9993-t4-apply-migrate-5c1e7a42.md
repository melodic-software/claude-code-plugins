---
bump: patch
---

### Added

- Eval case `t4-apply-migrate`, turn 2 of setup scenario T4 on the legacy `tarnquill` copy. It resumes a recorded `/developer-experience:setup check` turn that reports the `.claude/` conventions file as an old location, then runs `/developer-experience:setup apply`. Its free graders check that `docs/conventions/developer-experience.md` is created, that a shell call removes or moves `.claude/developer-experience.md`, that `AGENTS.md` holds exactly one pointer line and it names the new path, and that `CLAUDE.md` stays byte for byte as seeded. ([#9993](https://github.com/melodic-software/claude-code-plugins/issues/9993))
