---
description: "Find the seeded defect in a diff: a refactor of scripts/check_fields.py turns `value < low` into `value <= low`, so a field at its inclusive minimum is reported, beside a str.format rewrite of check_env's message that prints the same text and must not be flagged"
tags: [routing, review]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Exactly one finding line, naming bound_problem or check_bounds: `value <= low` reports a value equal to its inclusive minimum, so runs: 1, max_turns: 1 or timeout_seconds: 1 is called below the minimum. The check_env message change is not a finding."
---

`change.diff` is a proposed change to the files in the current directory, which already hold the changed version. Review the change: find each defect it introduces, meaning a place where the changed code behaves wrongly. Style, naming and missing tests are not defects, and neither is a problem the change did not introduce.

Reply with one line per defect, in this form:

finding: <file> <function> - <what goes wrong, and for which input>

Write one line for a defect however many consequences it has. When the change introduces no defect, reply with the single line `finding: none`.
