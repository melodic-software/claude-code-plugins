---
bump: patch
---

### Fixed

- **`write` and `plan` no longer say the Bash tool returns a command's complete output into context.** The decision stands (the pipe is the bound, so it belongs in the command); the reason now points at the Output limits section of the Claude Code tools reference for what a result delivers inline.

### Changed

- **The pre-compute guidance in `write` and `plan` points at the docs instead of restating harness behavior.** Both keep their git reads as separate body Bash calls and cite the worktree skill's gather-block record and the skills page's section on how injected commands run, with an as-of date and a recheck trigger.
