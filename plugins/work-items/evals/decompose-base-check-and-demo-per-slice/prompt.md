---
description: 'Legacy decompose 13. A full draft breakdown with the base-commit check: AC2 flagged as already passing and asked about by name, a Demo line per item with the demo question, nothing published. demo-line reads the reply for a Demo field. Read-only tools, graded on the reply.'
tags: [decompose, acceptance-criteria, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Runs the base-commit check against the default branch''s current commit: AC1 fails there, AC2 already passes and is flagged. The Step 3 round names the base commit and asks by name whether to sharpen AC2 until it fails at base, leave it out as already met, or keep it with a one-line reason, shows a Demo line for each item (for the flag slice, running the export for one month and seeing only that month''s refunds) and asks what each slice demos. Nothing is published before approval.'
---

/work-items:decompose

The topic is refund-export and its approved PLAN.md has one phase, Phase 1: add a `--month` flag to the refund export. Its acceptance criteria are AC1: `refunds export --month 2026-09` writes only September refunds, and AC2: `refunds export --help` exits 0. There is no checkout; take these facts as read from the default branch's current commit: the export command exists and its `--help` already exits 0, and it has no `--month` flag. Draft the breakdown.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
