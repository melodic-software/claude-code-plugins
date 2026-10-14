---
description: "teach exercise writes a one-concept practice file in the documented format (title, Concept, Difficulty, Prerequisites, then Setup, Task, three progressive hints and Solution) tied to the workspace mission's own tables"
tags: [education, teach, outcome, exercise, scaffold]
max_turns: 20
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "MISSION.md is read; the printed exercise.md has '# Exercise:', Concept, a beginner/intermediate/advanced Difficulty and Prerequisites lines, then Setup, Task, Hints with three numbered hints, and Solution in that order, practicing LEFT JOIN on the mission's orders and customers tables."
---

/education:teach exercise left-join

My sql-joins topic workspace is at learning/topic/sql-joins/ in this directory; use it as the active workspace. This run cannot write files, so print the complete exercise.md in your reply instead of writing it.
