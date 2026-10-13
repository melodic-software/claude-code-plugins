---
bump: patch
---

### Fixed

- **`/bugs:write` no longer says where `/bug` sends a report.** Where it goes now depends on how the person is connected, so the boundary and its record point at the live `/bug` row. The skill still offers `/bug` only for defects in Claude Code itself and never runs it.
- **`/bugs:write` no longer says the Bash tool returns a command's complete output.** The decision, put the bound in the pipe, stays; how much output reaches the result is read at the tools reference's output limits section.

### Changed

- **Copied upstream specifics become anchored pointer records.** The pre-compute note in `write` and `scan` points at the gather-block record and the skills page section on injected commands; `scan` points at the string-substitution section for `${CLAUDE_EFFORT}`; `setup` and the README read where plugin option values are stored from the live sections instead of restating it.
