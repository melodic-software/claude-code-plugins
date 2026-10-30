---
description: "Find the seeded defect in a diff: a change to scripts/resolve-roles.sh swaps the order of json_str's two escapes, so a quote in the target or a note breaks the JSON, beside a behavior-preserving refactor of the note helpers that must not be flagged"
tags: [routing, review]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Exactly one finding line, naming json_str: escaping quotes before backslashes doubles the backslash added before each quote, so the string ends early and the JSON is invalid. The shared note helper is not a finding."
---

`change.diff` is a proposed change to the files in the current directory, which already hold the changed version. Review the change: find each defect it introduces, meaning a place where the changed code behaves wrongly. Style, naming and missing tests are not defects, and neither is a problem the change did not introduce.

Reply with one line per defect, in this form:

finding: <file> <function> - <what goes wrong, and for which input>

Write one line for a defect however many consequences it has. When the change introduces no defect, reply with the single line `finding: none`.
