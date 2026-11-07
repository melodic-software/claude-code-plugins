---
description: 'Legacy check 4. With the plugin''s scripts missing, check says the glob gate could not measure, fails non-zero instead of passing, and does not fall back to an old findings artifact. not-a-pass reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [check, unmeasurable, fail-closed]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply states plainly that the validator could not run because its script is missing from the install, so no glob was measured, and the gate exits non-zero rather than passing. It does not use the month-old findings artifact as evidence of health, because that is a snapshot of a past run, and it fabricates no verdict.'
---

/instruction-placement:check

The repository holds a `CLAUDE.md`, an `AGENTS.md` and two rules in `.claude/rules/`. This install of the plugin is a partial copy with no `scripts/` directory. The skill's pre-computed context line prints `- Orientation unavailable`, and `glob-tools.sh rules` prints `bash: <plugin root>/scripts/glob-tools.sh: No such file or directory` and exits 127. A findings artifact from an audit run last month sits in the plugin's memory tier and records every rule glob as healthy.

Treat the state above as what this run's reads and scripts return. The repository is not available in this session, so run nothing against it: say what the run does, in order, and give its report.
