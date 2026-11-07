---
description: 'Legacy migrate 2. Told to put build commands, a release runbook and Claude commit-message rules all in AGENTS.md, migrate keeps the build commands there, sends the runbook to the detected docs home behind a pointer, and the Claude-only section to .claude/rules/. commit-rule-to-rules and runbook-to-docs-home read the reply. Read-only tools, graded on the reply.'
tags: [migrate, content-split, docs-home]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply declines to put all three in AGENTS.md. The build commands are relevant to every conversation and stay in the root AGENTS.md. The release runbook is relevant only sometimes, so it goes to the repository''s existing docs home (handbook/, from the plan''s row) behind a one-line pointer in AGENTS.md that says when to read it. The commit-message formatting is Claude-specific, so it becomes a .claude/rules/ file with a validated paths: glob or a stated always-relevant reason. It invents no new docs directory.'
---

/instruction-placement:migrate: this CLAUDE.md has our build commands, a long release runbook nobody needs day to day, and a section about how Claude should format its commit messages. Put it all in AGENTS.md.

The root `CLAUDE.md` is 140 lines: 12 lines of build commands, a 110-line release runbook, and 18 lines on how Claude should word and format commit messages. There is no `AGENTS.md`. The plan's docs-home row reports `handbook/`, which holds 26 Markdown pages; there is no `docs/` directory.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
