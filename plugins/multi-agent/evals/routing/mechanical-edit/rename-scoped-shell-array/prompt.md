---
description: "Scoped rename: the NOTES array becomes ROLE_NOTES in scripts/resolve-roles.sh only, while scripts/route.sh keeps its own NOTES array and the notes_json variable and JSON key stay as they are"
tags: [routing, mechanical-edit]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Edit, Write]
expected_outcome: "scripts/resolve-roles.sh holds ROLE_NOTES at all 5 places NOTES was and no bare NOTES; notes_json and the notes JSON key are unchanged; scripts/route.sh still has NOTES 4 times"
---

In `scripts/resolve-roles.sh`, rename the Bash array `NOTES` to `ROLE_NOTES`. Rename it in that file
only, and change nothing else.
