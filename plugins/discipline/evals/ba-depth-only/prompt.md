---
description: "The depth argument: the reply runs the depth pass and the outside check only, says Altitude and Range were skipped and why, and executes nothing."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Raises the parser request on depth only (expert additions, real export rows as raw material, named methods, an outside check), states that Altitude and Range were skipped with a reason, raises no bigger goal and brings in no other field; no Write, Edit or Bash call."
---

/discipline:be-ambitious depth Write a Python function that parses the dates in our nightly CSV export.
