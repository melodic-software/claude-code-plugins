---
tags: ['reduce']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Scans the docs altitude for cross-document coupling, verifies findings, ranks them, writes the ledger, and stops — no file edits outside the ledger, no branch, no push, no tracker items.'
---

/coupling:reduce dry-run docs
