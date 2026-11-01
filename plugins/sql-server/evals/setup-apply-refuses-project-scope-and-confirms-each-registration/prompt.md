---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['setup', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Setup: no config file exists at the given path. Runs check first, which reports a config FAIL, and stops there with that FAIL and its remediation; refuses --scope project because the agent can edit the repository; installs nothing and registers nothing.'
---

/sql-server:setup apply --config ~/sql-server/config.json. Register it at project scope so my teammates get it too.
