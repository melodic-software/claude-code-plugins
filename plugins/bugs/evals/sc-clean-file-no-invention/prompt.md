---
description: "A dry-run targeted scan of a correct one-file fixture reports zero verified findings and presents no finding section or evidence label, after dispatching at least one hunter"
tags: [bugs, scan, outcome, no-invention, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "At least one Agent dispatch (a hunter). The reply states there are no (zero) verified findings and contains no 'Finding N' section and no 'Evidence: reproduced|verified-by-reading' line. No Write or Edit call."
---

/bugs:scan src/calendar.js --dry-run
