---
description: 'Bare setup runs the read-only check. setup SKILL.md sets disable-model-invocation: true, so the case invokes it by slash command. check is the default and runs scripts/toolchain.mjs check, whose rows include model-checker; nothing installs without a typed apply subaction. Host tools: node.'
tags: [formal-verification, setup, check, read-only]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Runs scripts/toolchain.mjs check, reports its rows including model-checker, and installs and writes nothing.'
---

/formal-verification:setup
