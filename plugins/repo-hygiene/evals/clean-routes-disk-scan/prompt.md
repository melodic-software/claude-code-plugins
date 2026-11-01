---
description: "Routing in plain words. SKILL.md line 2 (description): 'Use when reclaiming disk space in a repo'; action-router.md line 46: disk-space phrases resolve to scan; SKILL.md line 175: scan is a read-only inventory and the run stops there; line 93: nothing mutates without dry-run and confirmation. The prompt names no slash command, so routes-to-clean is the Skill indicator (excluded from scoring). Bash is granted so scan.sh can run and so no-removal can fail. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, routing]
max_turns: 20
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The clean skill is invoked and runs scan.sh; the reply reports reclaimable sizes; dist/bundle.js still exists and no removal command runs."
---

This repo has grown way past what the source code should take on disk. What's eating the space, and how much of it could I get back?
