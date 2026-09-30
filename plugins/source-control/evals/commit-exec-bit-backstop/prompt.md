---
description: Run the exec-bit check as a command when committing new shebang scripts
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: exec-bit-check.sh --fix runs as a Bash command before the commit
---

I just wrote three new shell scripts under tools/ (each starts with #!/usr/bin/env bash). Stage and commit them.
