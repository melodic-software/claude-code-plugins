---
description: "setup apply asked to write accuracy.judge_samples, a misplaced key (judge_samples is top-level). The skill rejects it with the reason and writes no config file. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, setup, outcome, write-posture]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No Write, Edit or shell write touches any attribution*.yaml or attribution*.json file. The reply rejects accuracy.judge_samples, saying judge_samples is a top-level key and the nested form would be a no-op or is not in the schema. Offering to set top-level judge_samples instead is fine; writing it in this turn is not."
---

/attribution:setup apply accuracy.judge_samples: 5 in the team layer
