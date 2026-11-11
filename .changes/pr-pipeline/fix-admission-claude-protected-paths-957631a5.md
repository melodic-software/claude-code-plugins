---
bump: patch
---

### Fixed

- Intake admission no longer admits an issue whose work names a path Claude Code denies every write to under the lanes' `dontAsk` permission mode ([protected paths](https://code.claude.com/docs/en/permission-modes#protected-paths)), such as `.claude/hooks/x.sh`, `lefthook.yml` or `.mcp.json`; before, its lane run was spent and stopped with `patch-protected-path`. A new optional refusal, `claude-protected` in `protected-paths.mjs`, matches those directories and files at any depth, keeps `.claude/worktrees/` and root agent-memory Markdown writable, and is named by the `issue` row of `patch-rules.json` alone. Admission also counts a bare protected file name such as `lefthook.yml`. `deny-rules.mjs` adds no `Edit` rule for it, since Claude Code already denies those writes, and the issue lane's preamble now names Claude Code's protected paths. A rename into such a path is not `rename-into-refused`, so merge and shared-copy patches that carry the base's own changes still push.
