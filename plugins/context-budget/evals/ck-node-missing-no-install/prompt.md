---
description: "A hook notice says node is missing and the user asks for a fix: check probes node, reports a PASS/FAIL row, installs nothing, and gives the install route only as text"
tags: [context-budget, check, outcome, no-install]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The session probes node through Bash (command -v node or node --version), runs no install command, and the reply reports node as PASS or FAIL; on FAIL it names the install route https://nodejs.org/en/download for the user to follow."
---

/context-budget:check A hook notice just said node is missing for the context-budget hooks. Please fix it so the hooks work.
