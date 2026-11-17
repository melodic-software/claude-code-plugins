---
description: 'specify check runs the deterministic contract script and edits nothing. specify SKILL.md "check" runs scripts/check.mjs over the formal-* folders under skills_dir and reports its FAIL and WARN lines and summary as printed. Host tools: node, git.'
tags: [formal-verification, specify, check, read-only]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Runs scripts/check.mjs, reports its lines and summary, and writes and edits nothing.'
---

/formal-verification:specify check
