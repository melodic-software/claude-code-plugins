---
description: "Legacy setup 6: the scaffold's repository tracks discipline.yaml holding lever_scope: always. SKILL.md lines 77-91: the row is a WARN quoting file, key and value, the invalid layer is dropped and the effective value is deterministic, never a FAIL, and check writes nothing. warn-row needs one line with WARN, discipline.yaml, lever_scope and always; effective-deterministic the effective value; no-fail no unnegated FAIL; no-apply-call and no-shell-write forbid writes, file-unchanged reads the file as seeded after the run. Held: legacy expectation 2's 'not the user's non-trivial' half, since a run cannot set the user option and unset also resolves deterministic. Needs --scaffold and --allow-tools Bash, with a real node first on PATH."
tags: [discipline, setup, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "A WARN naming docs/conventions/discipline.yaml, lever_scope and always, the effective lever_scope reported as deterministic, no FAIL, and no write."
---

/discipline:setup check
