---
description: "Asked which skills to turn off, the audit sends the person to /skill-doctor and picks no skills itself"
tags: [context-budget, audit, outcome, route-out]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply tells the person to run /skill-doctor themselves to choose which skills to turn off, names no specific skill to turn off, and may offer to measure the saving after a toggle."
---

/context-budget:audit Which of my skills should I turn off to save context?
