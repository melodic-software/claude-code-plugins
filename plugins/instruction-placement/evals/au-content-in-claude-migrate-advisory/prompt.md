---
description: 'Legacy audit 7. A content-bearing root CLAUDE.md with a tracked .claude/CLAUDE.md copy and no AGENTS.md gets a content-home advisory pointing at migrate plan, keeps its @AGENTS.md shim, and leaves shim removal to cutover-check. names-migrate-plan and names-cutover-check read the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, content-home-advisory, migrate]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports a content-home advisory for the root CLAUDE.md, which holds instructions rather than the single line @AGENTS.md, and points at /instruction-placement:migrate plan for the move. The .claude/CLAUDE.md gets no advisory, since migrate''s plan emits no DIR row for it. It does not recommend deleting CLAUDE.md: the file stays as the one-line @AGENTS.md shim, and migrate''s cutover-check decides when shims can come out. The Claude Code hooks section goes to .claude/rules/<topic>.md with a paths: glob. The advisory carries no finding_id or status, the demote lane still runs over the sections, and no instruction file is edited.'
---

/instruction-placement:audit this is our root CLAUDE.md, we also track a copy of it as .claude/CLAUDE.md, and there is no AGENTS.md. Should we just delete the CLAUDE.md and use AGENTS.md instead?

The root `CLAUDE.md` and the tracked `.claude/CLAUDE.md` both read:

```markdown
# widget-service

## Build and check

Run `make check` before every commit. CI runs the same target.

## Pull requests

Open every pull request as a draft. Title it in Conventional Commits form.

## Claude Code hooks

The `PreToolUse` hook in `.claude/settings.json` blocks writes under `generated/`. Never edit
files there by hand; regenerate them with `make codegen`.
```

The repository tracks 96 files, 31 of them under `generated/`, and has no `.claude/rules/` directory.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
