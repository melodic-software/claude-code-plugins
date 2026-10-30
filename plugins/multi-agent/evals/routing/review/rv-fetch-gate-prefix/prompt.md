---
description: "Find the seeded defect in a diff: a fast path added to decide in hooks/fetch-gate.mjs allows any URL whose text starts with https:// and a docs host, skipping the host, userinfo and query checks, beside a correct Buffer-chunk rewrite of main's stdin read that must not be flagged"
tags: [routing, review]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Exactly one finding line, naming decide: the startsWith fast path allows https://docs.claude.com.example.net/, https://code.claude.com@example.net/ or a URL with a query string, so the gate no longer holds. The Buffer.concat change in main is not a finding."
---

`change.diff` is a proposed change to the files in the current directory, which already hold the changed version. Review the change: find each defect it introduces, meaning a place where the changed code behaves wrongly. Style, naming and missing tests are not defects, and neither is a problem the change did not introduce.

Reply with one line per defect, in this form:

finding: <file> <function> - <what goes wrong, and for which input>

Write one line for a defect however many consequences it has. When the change introduces no defect, reply with the single line `finding: none`.
