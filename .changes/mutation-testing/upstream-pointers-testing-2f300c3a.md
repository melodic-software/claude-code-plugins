---
bump: patch
---

### Fixed

- **`audit` no longer says the Bash tool returns a command's complete output into context.** The decision stands (the pipe is the bound, so it belongs in the command); the reason now points at the Output limits section of the Claude Code tools reference for what a result delivers inline.

### Changed

- **`audit` cites its sources for harness behavior it relies on.** The pre-compute guidance keeps git reads as separate body Bash calls and points at the worktree skill's gather-block record and the skills page's section on how injected commands run; the effort cap points at the skills page's string-substitution section. Each pointer carries an as-of date and a recheck trigger.
