---
description: 'Legacy setup 4. On a fresh repository, setup reports that no index exists yet as a starting state distinct from UNREACHABLE, names the file the resolution order would pick, says the plugin works with zero configuration, and does not gate a first audit behind setup. no-index-yet reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, rules-index, first-run]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports that no index block exists yet and treats it as a starting state, not a defect, distinct from UNREACHABLE, which means the file exists and is never read (here the root CLAUDE.md imports AGENTS.md, so it is reachable). It names the root AGENTS.md as the file the resolution order would pick for the index, confirms the plugin works with no configuration because every setting has a working default, and does not make setup or configuration a prerequisite for a first audit.'
---

/instruction-placement:setup: fresh repo, we've never run this before.

The root `CLAUDE.md` is the single line `@AGENTS.md`. The root `AGENTS.md` is 40 lines of build and style conventions and nothing else. There are two rules in `.claude/rules/`, each with a `paths:` glob that resolves. `git`, `jq` and the Claude Code CLI are on `PATH`.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
