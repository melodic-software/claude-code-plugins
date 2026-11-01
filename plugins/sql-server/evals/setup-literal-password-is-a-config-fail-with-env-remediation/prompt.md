---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides. Needs --allow-tools Bash: the skill runs check-setup.mjs.'
tags: ['setup', 'narration']
allowed_tools: [Read, Glob, Grep, Bash, Skill]
expected_outcome: 'Setup: no config file exists at the given path, so the script''s config row is a FAIL for the missing file. Reports that FAIL and, for the literal password the user describes, the remediation to replace it with { "env": "<VARIABLE>" } and set that variable in the environment Claude Code starts in, never echoing the password value.'
---

/sql-server:setup check --config ~/sql-server/config.json. My config has "password": "Hunter2!" for the dev environment.
