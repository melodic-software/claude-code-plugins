---
description: "A library with one deep export gets an explicit no-candidates verdict; its private helpers are not carded as shallow and its recorded in-process decision stands"
tags: [architecture, improve, row19, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "Scans the library, finds buildToc already deep (one export over parsing, slug de-duplication and nesting, tested only through it), and says plainly that there is no deepening candidate, with no Strong or Worth exploring card, and leaves the recorded decision to parse headings in-process standing"
---

/architecture:improve find deepening opportunities in this codebase.
