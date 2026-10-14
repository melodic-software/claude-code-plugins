---
description: "assess on a one-file rename returns single in exactly two lines with no shape line"
tags: [multi-agent, assess, outcome, single]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "The reply is exactly two lines, `verdict: single` and a `reason:` line, with no `shape:` line. No agent is spawned."
---

/multi-agent:assess Rename the local variable `cnt` to `count` inside the one 30-line function `sumScores` in src/util/math.ts.
