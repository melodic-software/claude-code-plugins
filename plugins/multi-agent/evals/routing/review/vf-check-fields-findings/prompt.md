---
description: "Verify four review findings against scripts/check_fields.py: confirm the two real defects (a mutable default list shared across calls, isinstance accepting a bool as an int) and refute the two false ones (finditer counting overlapping matches, sorted(dict) sorting values)"
tags: [routing, review]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "F1: confirmed. F2: refuted (finditer returns non-overlapping matches). F3: refuted (iterating a dict yields its keys). F4: confirmed."
---

`findings.md` lists findings a reviewer raised against the code in the current directory. Verify each one against the code: a finding is confirmed when the defect it describes is real and behaves as it says, and refuted when it is not.

Reply with one line per finding, in the order `findings.md` lists them, in this form:

F<n>: confirmed - <the evidence>
F<n>: refuted - <the evidence>
