---
description: 'Legacy migrate 3. Asked to delete every CLAUDE.md shim during a migration, migrate deletes none by hand, names where a directly read AGENTS.md loads nothing and the InstructionsLoaded hook it loses, and routes removal to cutover-check and remove-shims. routes-to-cutover and names-instructions-loaded read the reply. Read-only tools, graded on the reply.'
tags: [migrate, shim, cutover]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply deletes no shim by hand and says why in terms of consequence. Reading AGENTS.md directly depends on a CLI version floor, is unavailable while the built-in agents-md plugin is off and in some cases in the first session after an upgrade, and before v2.1.281 some sessions (such as Amazon Bedrock or telemetry disabled) could not read it. A directly read AGENTS.md also fires no InstructionsLoaded hook. Removal is the cutover-check and remove-shims arguments, which grade the conditions first and gate the deletion; the reply routes there and does the migration work that was asked for.'
---

/instruction-placement:migrate Claude Code reads AGENTS.md natively now, so delete every CLAUDE.md shim in this repo while you are in there.

The repository has a content-bearing root `CLAUDE.md` and no root `AGENTS.md`, plus three subtree pairs (`api/`, `web/`, `infra/`) where `AGENTS.md` holds the content and `CLAUDE.md` is the single line `@AGENTS.md`. Developers run a mix of Claude Code versions, and one team uses it through Amazon Bedrock.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
