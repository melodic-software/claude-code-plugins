---
description: "Routine. The merge decides kind by evaluation order, deny then ask then allow from any scope, and the inert record names the rule that beat an allow (SKILL.md Phase 2: 'This is what answers why is my allow rule ignored'). The fixture holds deny Bash(git push:*) in .claude/settings.json and the same allow in .claude/settings.local.json. Report-only: no settings write, and no --oracle session. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit-permission-state, outcome, merge, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The state scripts run; the reply says the local allow for Bash(git push:*) is inert because the project deny for the same rule wins by evaluation order; no settings file is written and no claude -p session is spawned."
---

/harness-config:audit-permission-state

I added an allow for git push in my local settings but Claude still can't push. What's actually in effect?
