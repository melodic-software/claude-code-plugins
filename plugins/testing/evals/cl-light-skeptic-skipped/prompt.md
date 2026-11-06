---
description: "A clean feature branch with assertion-free tests in tests/billing, in a repository whose default branch sets verification: light in docs/conventions/testing.yaml. Cannot-fail-only mode dispatches no skeptic, writes the skip token as the skeptic verdict, clears no row and deletes no test. Needs --scaffold --allow-tools Bash Write Agent."
tags: [testing, cleanup, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no skeptic; writes verification: skipped (light); edits or deletes no test in tests/billing."
---

/testing:cleanup tests/billing --cannot-fail-only
