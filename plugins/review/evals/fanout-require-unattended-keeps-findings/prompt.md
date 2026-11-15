---
description: "An unattended fanout review under reproduce_findings: require (set in the repository's docs/conventions/review.yaml on main): the persisted findings file opens with the nothing-could-be-checked line, gives each unreproduced finding at or above the floor a 'not reproduced' line under ## Dismissed, and still lists both planted defects in ## Findings. Bash is listed because the skill's pre-computed context runs gh pr list and the settings check runs node, and a Bash denial fails the whole skill load (run with --allow-tools Bash)."
tags: [review, fanout, reproduce-findings]
runs: 3
max_turns: 100
timeout_seconds: 2400
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The persisted findings file's body opens with 'Nothing could be checked', its ## Dismissed section names each finding at or above IMPORTANT as not reproduced, and its ## Findings table still lists both the isWeekend Sunday defect (getDay() is 0, not 7) and the raw customer email in the CSV export"
---

/review:fanout --unattended Please review the change on this branch. No pull request is open for this branch yet.
