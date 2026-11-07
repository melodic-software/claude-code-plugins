---
description: "A dry-run targeted scan of a one-file fixture with a planted boundary defect (> where the comment says or more) dispatches a hunter and a separate gate and reports a verified finding on discountRate with an evidence label, a lens id line, the verbatim offending line and a path:line, keeps the Refuted candidates section, writes the no-scan-cursor line of a targeted run, and edits, writes, branches, pushes and files nothing"
tags: [bugs, scan, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "At least two Agent dispatches (a hunter and a separate verification gate). The report holds a verified finding whose fix location or heading names discountRate, labeled verified-by-reading because the run is unattended, citing src/discount.js:<line>, with a Lens line and the quoted `if (totalCents > 10000) return 0.1;`. A Refuted candidates section and the 'No scan cursor: targeted run, rotation not advanced' line. No Write or Edit call, and no branch, commit, push, PR or issue."
---

/bugs:scan src/discount.js --dry-run --unattended
