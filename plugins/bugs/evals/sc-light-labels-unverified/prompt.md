---
description: "A repository whose default branch sets verification: light in docs/conventions/bugs.yaml: a dry-run targeted scan of a planted boundary defect dispatches hunters but no refuting gate, writes the skip token, and reports the candidate with Evidence: unverified rather than verified-by-reading"
tags: [bugs, scan, setting, verification-level, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no gate subagent; writes verification: skipped (light); the discountRate candidate carries Evidence: unverified."
---

/bugs:scan src/discount.js --dry-run --unattended
