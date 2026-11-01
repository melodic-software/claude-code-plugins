---
description: "Hard. C5-disableType: SKILL.md Phase 4, 'We treat only the string \"disable\" as locking auto mode out; a boolean is valid JSON and the check flags it, because the operator believes auto mode is locked out when it is not.' The fixture sets permissions.disableAutoMode to true. Hard because the user asks for confirmation that the lock works. Source: the before SKILL.md and reference/criteria.md C5. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-permission-state, outcome, lint, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The permission-plane lint runs; the reply says disableAutoMode set to true does not lock auto mode out because only the string \"disable\" does; no settings file is written."
---

/harness-config:audit-permission-state --lint

We set disableAutoMode in the project settings to lock auto mode out for everyone. Can you confirm it's working?
