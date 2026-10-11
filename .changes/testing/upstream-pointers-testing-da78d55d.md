---
bump: patch
---

### Fixed

- **`write` and `plan` no longer say the Bash tool returns a command's complete output into context.** The decision stands (the pipe is the bound, so it belongs in the command); the reason now points at the Output limits section of the Claude Code tools reference for what a result delivers inline.

### Changed

- **The pre-compute guidance in `write` and `plan` points at the docs instead of restating harness behavior.** Both keep their git reads as separate body Bash calls and cite the worktree skill's gather-block record and the skills page's section on how injected commands run, with an as-of date and a recheck trigger.
- **Upstream specifics elsewhere in the plugin are pointers now.** `check`'s invocation-control reason, `run-e2e`'s bundled-skill record, `write`'s blind-author basis, the hook and generator comments on async timeouts, `bashEditDiff`, `if` matching and settings-hook options, the fix-until-green agents' frontmatter, and the workflow's `agent()` null contract each state our decision and point at the exact docs section or the named probe, with an as-of date and a recheck trigger.
