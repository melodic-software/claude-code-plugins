---
description: 'The scaffold repository compares the magic status string "archived" in eleven files under src/orders/, and its default branch sets verification: light in docs/conventions/coupling.yaml: phase C reads the level, reproduces nothing, writes the skip token, ledgers the finding with evidence-verified: false, labeled unverified, and keeps it out of the apply lane, so no file under src/orders is edited and nothing is committed.'
tags: ['reduce', 'verification-level', 'scaffold']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 40
timeout_seconds: 900
expected_outcome: 'Runs lib/read-verification.sh and reports verification: light; writes verification: skipped (light); ledgers the magic-string finding with evidence-verified: false, labeled unverified and report-only; edits no file under src/orders and makes no commit.'
---

/coupling:reduce

This repo has a magic status string compared in eleven call sites.
