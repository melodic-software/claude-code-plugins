---
description: "Padded deploy notes and a verbose helper: the run must cut the filler, the unused parameter and the dead branch, and keep every rule (backup ordering, never on Fridays, at least 3 replicas) and the boundary TypeError check"
tags: [discipline, tighten-your-output, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "docs/deploy-notes.md loses its filler phrases but keeps all three rules with their qualifiers; src/util.py loses legacy_mode and the else/pass branch but keeps raise TypeError."
---

/discipline:tighten-your-output docs/deploy-notes.md and src/util.py, both written earlier this session
