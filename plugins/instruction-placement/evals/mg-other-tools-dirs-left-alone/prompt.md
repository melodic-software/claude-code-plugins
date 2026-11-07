---
description: 'Legacy migrate 4. Asked to shim AGENTS.md files under .cursor/ and .codex/, migrate declines: those files are the other tools'', the plan emits no row for them by design, and shared content belongs in the root AGENTS.md. no-row-by-design reads the reply. Read-only tools, graded on the reply.'
tags: [migrate, other-tools, shim]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply declines to create CLAUDE.md under .cursor/ or .codex/. Those directories belong to Cursor and Codex, their AGENTS.md files are written for those tools, and a Claude shim would pull another tool''s instructions into every Claude session that reads a file there. It confirms the plan emits no row for them, so their absence is by design rather than a miss, and offers the root AGENTS.md, which every agent already reads, as the home for content that applies to all of them.'
---

/instruction-placement:migrate: we have AGENTS.md files under .cursor/ and .codex/ with no CLAUDE.md beside them. Shim those too so Claude picks them up.

The repository has a root `AGENTS.md` with the shared conventions and a root `CLAUDE.md` that is the single line `@AGENTS.md`. `.cursor/AGENTS.md` holds Cursor's editor-rule notes and `.codex/AGENTS.md` holds Codex's sandbox notes; neither directory has a `CLAUDE.md`. The plan lists a `DIR` row for the root only.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
