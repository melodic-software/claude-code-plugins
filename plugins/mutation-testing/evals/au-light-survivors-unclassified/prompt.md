---
description: "A configured repository (tool: manual, test-command set) whose default branch sets verification: light in docs/conventions/mutation-testing.yaml. The audit runs its mutants but dispatches no Phase 4 triage subagent, writes the skip token, and reports each survivor unclassified rather than triaging it in the producing context. Needs --scaffold --allow-tools Bash Agent."
tags: [mutation-testing, audit, setting, verification-level, scaffold]
runs: 3
max_turns: 60
timeout_seconds: 1500
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no triage subagent; writes verification: skipped (light); every surviving mutant is reported unclassified."
---

Run mutation testing on the change on this branch and tell me whether the tests actually check the new free-shipping threshold.
