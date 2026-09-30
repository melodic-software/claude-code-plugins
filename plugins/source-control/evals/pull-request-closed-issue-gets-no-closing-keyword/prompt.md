---
description: Do not add a closing keyword for an issue that is already closed
tags: [pull-request, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: No Closes, Fixes, or Resolves keyword for #321 appears in any command
---

Create the pull request from branch fix/321-stale-link. GitHub reports issue #321 exists but its state is CLOSED.
