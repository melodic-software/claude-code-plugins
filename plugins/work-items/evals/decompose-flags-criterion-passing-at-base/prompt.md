---
description: "The base-commit check flags an acceptance criterion that already passes at the base commit and leaves the ones that fail there unflagged"
tags: [decompose, acceptance-criteria]
runs: 3
max_turns: 20
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Runs the base-commit check, flags AC2 as already passing at base, does not flag AC1 or AC3, and asks whether to sharpen AC2 or leave it out as met"
---

Load /work-items:decompose and run its base-commit check on the acceptance criteria below. Report
one line per criterion id, then say what you would ask the user about them at Step 3. Publish
nothing.

- AC1: `refunds export --month 2026-09` writes only September refunds.
- AC2: `refunds export --help` exits 0.
- AC3: a test runs the export for one month and checks the row count.

You have no checkout. Take these facts as read from the base code: the `refunds export` command
exists and its `--help` exits 0 today; it has no `--month` flag; no test covers a monthly export.
