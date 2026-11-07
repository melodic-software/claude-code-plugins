---
description: 'Legacy setup 5. apply proof_level=thorough: the script prints one refusal line naming the allowed values, exits 1 and writes nothing; the skill reports path, live and strict and invents no level or file (setup SKILL.md apply steps 1-2). runs-apply grades the call with the value as given, names-allowed-levels the three levels in the reply, no-settings-file the absent file; no-invented-level (llm) legacy expectation 3 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, apply, refusal, scaffold, no-network, routine]
max_turns: 12
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'Runs setup-apply.mjs proof_level=thorough, reports the refusal and the allowed levels path, live and strict, and writes no file.'
---

/verification:setup apply proof_level=thorough
