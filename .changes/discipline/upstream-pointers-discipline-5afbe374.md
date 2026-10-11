---
bump: patch
---

### Changed

- **Subagent behavior is read live from the Claude Code subagents page.** The `SKILL.md` bodies of `setup`, `use-your-skills`, `scrutinize-dont-coast` and `sweep-all` no longer restate fork-mode defaults, fork tool inheritance, or skill-preload rules; each states its own decision and points at the exact section of that page, with an as-of date and a recheck trigger.
- **`setup` reports whether fork mode is on in this kind of session.** Its full-batch prerequisite step reads the fork-mode section live and reports what it states, instead of printing stored defaults.
