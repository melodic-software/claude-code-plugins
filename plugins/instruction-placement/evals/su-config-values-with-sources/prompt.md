---
description: 'Legacy setup 3. Asked why a **/*.md rule reads over-broad, setup check prints each setting with its source, the breadth ceiling as 75 from the default, says over-broad is advisory, and names breadth_max as the lever. breadth-75-default reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, configuration, over-broad]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply prints the effective configuration with a source for every value, so the surprising number is traceable: the breadth ceiling is 75 and it comes from the default, not configuration. A value equal to the default is still reported with its source, because 75 (default) and 75 (configured) are different facts. It explains that over-broad is advisory and never fails the gate, and names raising breadth_max as the lever for a repository where one extension legitimately covers most files.'
---

/instruction-placement:setup check: why is it calling our **/*.md rule over-broad?

The repository tracks 1,000 files, 880 of them Markdown, and `.claude/rules/prose.md` uses `paths: **/*.md`. The plugin has no `user_config` values set and the repository has no `.claude/instruction-placement.md`. The root `CLAUDE.md` is the single line `@AGENTS.md`, the root `AGENTS.md` carries an index block that matches both rules, and `git`, `jq` and the Claude Code CLI are on `PATH`.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
