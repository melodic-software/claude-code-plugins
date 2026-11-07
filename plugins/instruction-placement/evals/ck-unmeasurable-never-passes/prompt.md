---
description: 'Legacy check 4. In a folder that is not a git checkout, check says the glob gate could not measure, fails non-zero instead of passing, and does not fall back to an old findings artifact. not-a-pass reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [check, unmeasurable, fail-closed]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply states plainly that the validator could not run because this directory is not a git repository, so tracked-file discovery has nothing to read, and the gate exits non-zero rather than passing. It does not use the month-old findings artifact as evidence of health, because that is a snapshot of a past run, and it fabricates no verdict.'
---

/instruction-placement:check run it here (this directory is a plain folder, not a git checkout).

The folder holds a `CLAUDE.md`, an `AGENTS.md` and two rules in `.claude/rules/`. `glob-tools.sh rules` prints `fatal: not a git repository (or any of the parent directories): .git` and nothing else. A findings artifact from an audit run last month sits in the plugin's memory tier and records every rule glob as `valid`.

Treat the state above as what this run's reads and scripts return. The folder is not available in this session, so run nothing against it: say what the run does, in order, and give its report.
