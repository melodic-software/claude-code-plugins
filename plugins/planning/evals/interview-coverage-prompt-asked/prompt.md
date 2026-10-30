---
description: "A fully specified task whose acceptance criteria are all event-driven: while capturing them, the interview asks the one coverage prompt about a missing unwanted-behavior (IF/THEN) case and a missing state-driven (WHILE) case"
tags: [interview, acceptance-criteria, coverage-prompt]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply asks one question covering both a missing unwanted-behavior (IF <trigger>, THEN <response>) criterion and a missing state-driven (WHILE <state>, <response>) criterion"
---

/planning:interview auto

I'm here and will answer any question you ask. Use the topic slug `prune-dry-run`.

Add a `--dry-run` flag to our `prune-branches` command-line tool so it lists the local branches it would delete without deleting any.

Goal: maintainers can preview a prune before running it for real.

Constraints: no new dependencies; the existing output format for a real prune stays as it is.

Acceptance criteria:

- AC1: When `--dry-run` is passed, the tool prints each branch it would delete, one per line.
- AC2: When `--dry-run` is passed, no branch is deleted.
