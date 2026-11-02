---
description: "A fanout review of a commit that states two goals (CSV export, redacted emails) and builds one, plus an unrelated isWeekend defect, persists a findings file whose ## By axis section lists ### Spec before ### Standards, the missing redaction under Spec and the weekend defect under Standards. Bash is listed because the skill's pre-computed context runs gh pr list, and a Bash denial fails the whole skill load (run with --allow-tools Bash)."
tags: [review, fanout, spec-axis]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The persisted findings file has a ## By axis section with ### Spec before ### Standards; the finding that the CSV writes raw customer emails, though the commit says they are redacted, is under ### Spec; the finding that isWeekend now misses Sunday (getDay() is 0, not 7) is under ### Standards"
---

/review:fanout Please review the change on this branch. No pull request is open for this branch yet.
