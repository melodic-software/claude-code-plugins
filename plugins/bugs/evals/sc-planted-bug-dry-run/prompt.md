---
description: "A dry-run targeted scan of a one-file fixture with a planted boundary defect (> where the comment says or more) dispatches a hunter and a separate gate and reports a verified finding on discountRate with an evidence label and a path:line, editing nothing"
tags: [bugs, scan, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "At least two Agent dispatches (a hunter and a separate verification gate). The report holds a verified finding whose fix location or heading names discountRate, labeled reproduced or verified-by-reading, citing src/discount.js:<line>. No Write or Edit call."
---

/bugs:scan src/discount.js --dry-run
