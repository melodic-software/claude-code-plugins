---
description: "A repository whose default branch sets verification: light runs no fresh-context answer-key pass for quiz-me; the key carries the skip token"
tags: [quiz-me, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/education.yaml at origin/main, writes the report and quiz for the slugify change, runs no fresh-context key pass, and marks the key verification: skipped (light)"
---

/education:quiz-me the slugify punctuation change on this branch
