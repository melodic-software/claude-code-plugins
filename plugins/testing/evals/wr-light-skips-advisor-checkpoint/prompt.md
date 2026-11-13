---
description: "New prorated-refund logic (money, HIGH risk) in a repository whose default branch sets verification: light in docs/conventions/testing.yaml: /testing:write writes the tests and skips the advisor checkpoint, reporting the skip token. Needs --scaffold --allow-tools Bash Write Edit."
tags: [write, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light, writes tests for refund_cents, calls no advisor, and reports verification: skipped (light)"
---

/testing:write Write the tests for billing/refund.py's refund_cents. It is new money logic.
