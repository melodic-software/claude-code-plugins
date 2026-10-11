---
description: "Sandbox probe without a scaffold, tagged sandbox-probe and no-trigger: records whether one plain Bash call runs in the eval's sandbox. Pairs with sandbox-probe-scaffold, which differs only by a scaffold that writes one file. Each grader records one fact, so the score is not a quality measure"
tags: [sandbox-probe, no-trigger]
runs: 1
max_turns: 5
timeout_seconds: 300
allowed_tools: [Bash]
expected_outcome: "Runs the one Bash command once, as written, and replies PROBE DONE"
---

This is an environment check, not a task to solve.

1. Run exactly one Bash call whose whole command is `echo sandbox-ok-7f3a`.
2. Whether it succeeds, fails or is refused, do not retry, change it, or run any other command.

Then reply with exactly `PROBE DONE` and nothing else.
