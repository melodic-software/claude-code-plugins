---
description: "Hard case. Why hard: Both steps are scripts that exist only in this plugin (`run-validity.py`, `noise-report.py`) with this repository's flag set; the blind base answers offered jq, bootstrap intervals, or nothing. Self-reference: every grader checks this plugin's own scripts."
tags: [reading-results, run-validity, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer runs `run-validity.py` on the file first and reports a number only on verdict VALID, then runs `noise-report.py` with `--threshold 0.8` and `--grader-agreement`, and says the +0.25 is a gain only when the noise verdict says the interval excludes 0"
---

My plugin eval finished cleanly at the default 3 runs with --keep-temp, and aggregate-result.json shows a mean delta of +0.25 across 6 cases, run with --threshold 0.8. Before I post that number in the team channel, what should I run on the file first? Give me the exact commands. Answer in under 150 words.
