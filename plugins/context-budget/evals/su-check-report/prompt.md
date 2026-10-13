---
description: "setup check reports a PASS/FAIL/INFO table, prints the Agent SDK install line for the operator without running it, and reports the settings-write-ask toggle with its fresh-session boundary"
tags: [context-budget, setup, outcome, check-only]
runs: 3
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "A markdown table with PASS/FAIL/INFO rows for node, the Claude Code CLI, the Agent SDK and the settings-write-ask toggle; the npm install --prefix line for @anthropic-ai/claude-agent-sdk is printed for the operator and never run; the toggle's value is stated and the reply says a change shows only in a fresh session."
---

/context-budget:setup check
