---
description: "teach status over one topic workspace shows one line with its mode, topic, record count, frontier concept, last-touched date and a due-for-review flag, excluding superseded records with a grep rather than loading record bodies"
tags: [education, teach, outcome, status, scaffold]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A grep for 'superseded' runs over the learning records; the reply has one line for topic/sql-joins with 2 records, the LEFT JOIN frontier and a due-for-review flag, and quotes no record body."
---

/education:teach status

My only workspace is at learning/topic/sql-joins/ in this directory (topic mode). This run cannot write files.
