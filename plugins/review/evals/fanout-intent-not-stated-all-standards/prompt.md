---
description: "A fanout review of a branch whose only commit says \"wip\", with a prompt that states no purpose, runs under `Intent: not stated`: the persisted findings file's ### Spec reads none and the weekend defect sits under ### Standards. Bash is listed because the skill's pre-computed context runs gh pr list, and a Bash denial fails the whole skill load (run with --allow-tools Bash)."
tags: [review, fanout, spec-axis]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The dispatched surfaces receive `Intent: not stated`; the persisted findings file's ## By axis section has ### Spec reading none, and the finding that isWeekend now misses Sunday (getDay() is 0, not 7) is under ### Standards"
---

/review:fanout Please review the change on this branch. No pull request is open for this branch yet.
