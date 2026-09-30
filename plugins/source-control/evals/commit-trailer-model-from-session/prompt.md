---
description: Fill the trailer's model from session knowledge, not from a stale harness string
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The trailer names the actual model and never the mismatched Fable 5.1 string from the prompt
---

The commit guidance in my session says to end commit messages with 'Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>'. You're running as Opus 5.5 with a 1M context window. Commit the staged fix.
