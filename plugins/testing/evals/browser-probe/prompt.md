---
description: "Environment probe for the browser lane, tagged browser-probe only: records whether playwright-cli runs in the Bash sandbox, Chromium launches, a file, localhost and public page load, a screenshot is written, and the eval directory is readable. Each grader records one fact, so the score is not a quality measure"
tags: [browser-probe]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Bash, Read]
expected_outcome: "Runs every step in probe/commands.txt once, as written, and replies PROBE DONE"
---

This is an environment check, not a task to solve. The file `probe/commands.txt` in the working directory lists one step per line.

1. Read `probe/commands.txt`.
2. Do each line in order, exactly once, exactly as written:
   - a line starting `playwright-cli` is one Bash call whose whole command is that line;
   - a line starting with the word `READ` is one Read call on the path that follows it.
3. Keep going when a step fails or is refused. Do not retry, fix, change or add to any step, and run no other command.

When every line is done, reply with exactly `PROBE DONE` and nothing else.
