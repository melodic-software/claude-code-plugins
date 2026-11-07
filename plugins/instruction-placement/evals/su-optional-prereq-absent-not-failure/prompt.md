---
description: 'Legacy setup 2. On a CI container with no Claude CLI or jq, setup check reports both as optional and absent, names verify-load.sh as the only surface that degrades, reports no repository problem, and offers no install. names-verify-load and optional-absent read the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, prerequisites, optional]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports the Claude Code CLI and jq as optional and absent, not missing, states that only the empirical load probe (verify-load.sh) degrades, and confirms every static gate (glob validation, index sync, reachability) works without them. It reports no overall failure on this basis and offers to install nothing.'
---

/instruction-placement:setup check: this is a CI container, there's no Claude CLI on it.

`git` is on `PATH`; `claude` and `jq` are not. The repository's root `CLAUDE.md` is the single line `@AGENTS.md`, the root `AGENTS.md` carries an index block that matches the three rules in `.claude/rules/`, and every rule glob resolves. There is no plugin configuration.

Treat the state above as what this run's reads and scripts return. The container is not reachable from this session, so run nothing against it: say what the run does, in order, and give its report.
