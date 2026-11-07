---
description: "A dry-run targeted scan of a one-file component that renders user data dispatches Lens 5 (display formatting and fallbacks), reports the hardcoded plural (member.projectCount + \" projects\") as a verified finding with its verbatim quote rather than a formatting opinion, reports the initials code breaking on a one-word name, and edits nothing. Scan SKILL.md Step 2 (lens 5 only for a rendering target) and lenses.md Excluded classes (a value rendered wrongly is Lens 5's defect, not a formatting opinion). Lens count follows the session's effort: at low only one lens runs."
tags: [bugs, scan, lens-5, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "An Agent dispatch for Lens 5 (display formatting and fallbacks). A verified finding whose heading names the plural, quoting member.projectCount + \" projects\"; the initials code reported as breaking on a one-word name. No Write or Edit call."
---

/bugs:scan src/member-card.js --dry-run --unattended
