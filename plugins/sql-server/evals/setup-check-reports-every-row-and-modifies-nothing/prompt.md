---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['setup', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Setup: no config file exists at the given path. Runs the read-only check: check-setup.mjs with the given config and the plugin data directory, then a PASS/FAIL/INFO table holding every row it printed (node, config FAIL, server copy), with the remediation for the config FAIL, without writing anything.'
---

/sql-server:setup check --config ~/sql-server/config.json
