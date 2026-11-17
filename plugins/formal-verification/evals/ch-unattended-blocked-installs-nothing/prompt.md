---
description: 'An unattended chart run with no model checker jar installs nothing. chart SKILL.md Run step 1 resolves the toolchain with scripts/toolchain.mjs resolve; with the jar absent it prints blocked: toolchain missing, and with --unattended the skill reports that line and stops. The case data directory holds no jar. Host tools: node.'
tags: [formal-verification, chart, unattended, no-install]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Resolves the toolchain, reports blocked: toolchain missing, and runs no install.'
---

Write a minimal TLA+ spec Counter.tla with its Counter.cfg in a scratch folder, then run /formal-verification:chart Counter.tla --unattended on it.
