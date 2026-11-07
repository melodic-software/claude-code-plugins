---
description: "A dry-run targeted scan of a one-file token-bucket limiter that renders nothing dispatches at least one hunter but no Lens 5 (display formatting and fallbacks) hunter, names the lenses it used (lens ids 1 to 4) in the reply, and edits nothing. Scan SKILL.md Step 2: dispatch lens 5 only when the scope renders user-facing data; the run metadata names the lens count (findings-report.md Run metadata)."
tags: [bugs, scan, lens-5, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "At least one Agent dispatch, none of them a Lens 5 (display formatting and fallbacks) hunter; the reply names the lens ids it ran (for example lens-1, lens-4). No Write or Edit call."
---

/bugs:scan src/rate-limiter.js --dry-run --unattended
