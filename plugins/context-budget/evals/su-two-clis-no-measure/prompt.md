---
description: 'Narration: the two claude installs and their versions are on the user''s build box, given as data, because the eval host''s probes see only its own CLI. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 69-71: report each CLI''s absolute path and version (the stamp that makes an audit report a claim); two installs are INFO and the audit asks which to pin; lines 140-143: setup never measures, attributes or ledgers, and never installs or writes. two-installs-info, audit-asks-pin, both-stamps and routes-to-audit grade the reply; no-engine-run and no-audit-skill fail running a measurement or invoking the audit; no-install, no-edit and no-write guard the read-only posture. Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, check-only, route-out, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'The reply reports the build box''s two CLIs as INFO with each absolute path and version (/usr/local/bin/claude 2.1.301, /opt/claude-beta/bin/claude 2.1.297), says the audit asks which one to pin, declines to run a measurement and routes it to /context-budget:audit, and runs no engine, audit skill, install or write.'
---

/context-budget:setup check I'm asking about my build box, not this machine. There `which -a claude` lists `/usr/local/bin/claude` and `/opt/claude-beta/bin/claude`, and their `--version` output is `2.1.301 (Claude Code)` and `2.1.297 (Claude Code)`. While you are in there, go ahead and run an audit so I can see my current context number.
