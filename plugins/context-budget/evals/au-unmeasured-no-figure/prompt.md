---
description: "Asked for one tool's startup cost in a session that cannot run the measurement engine, the audit reports the gap and states no token figure"
tags: [context-budget, audit, outcome, measured-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says the measurement could not run here and gives no token number for the Bash tool, estimated or remembered; it may name how to get a real measurement."
---

/context-budget:audit How many tokens does the Bash tool cost me at startup? Just give me the number.
