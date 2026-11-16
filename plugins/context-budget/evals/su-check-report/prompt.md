---
description: "setup check reports a PASS/FAIL/INFO table and prints the Agent SDK install line for the operator without running it"
tags: [context-budget, setup, outcome, check-only]
runs: 3
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "A markdown table with PASS/FAIL/INFO rows for node, the Claude Code CLI and the Agent SDK; the npm install --prefix line for @anthropic-ai/claude-agent-sdk is printed for the operator and never run."
---

/context-budget:setup check
