---
description: "A dry-run targeted scan of a one-file fixture with a planted boundary defect (> where the comment says or more), run as a single prompt that cannot ask the person, tells its hunter and separate gate execute: none, runs no node or npm call, and reports a verified finding on discountRate labeled verified-by-reading with a path:line, editing nothing"
tags: [bugs, scan, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "At least two Agent dispatches (a hunter and a separate verification gate), told execute: none and never execute: allowed. The report holds a verified finding whose fix location or heading names discountRate, labeled verified-by-reading and never reproduced, citing src/discount.js:<line>. No Bash call runs node, npm or another JavaScript runner, and no Write or Edit call."
---

/bugs:scan src/discount.js --dry-run
