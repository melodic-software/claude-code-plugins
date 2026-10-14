---
description: "A repo declares its standards index in CLAUDE.md; a new module swallows exceptions and misnames its function. The run must route through the index, load only the applicable docs, cite each broken doc, and correct the swallow in the file"
tags: [discipline, follow-our-standards, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit]
expected_outcome: "Reads docs/standards/README.md, does not read frontend-css.md, cites error-handling.md and naming.md for the two findings, and edits src/sync.py so no except block is followed only by pass."
---

/discipline:follow-our-standards audit src/sync.py, which we just wrote, against our standards
