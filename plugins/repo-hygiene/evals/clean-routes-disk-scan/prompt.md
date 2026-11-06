---
description: "Routing in plain words. SKILL.md line 2 (description): 'Use when reclaiming disk space in a repo'; action-router.md line 46: disk-space phrases resolve to scan; SKILL.md line 178: scan is a read-only inventory and the run stops there; line 96: nothing mutates without dry-run and confirmation; action-router.md line 66: scan has no user gate. The prompt names no slash command, so routes-to-clean is the Skill indicator (excluded from scoring). no-other-tier fails any other tier script, dry-runs included, since the request resolves to scan alone; no-scan-permission-ask fails a reply that asks leave to run the read-only scan (an offer of a later tier still passes). Bash is granted so scan.sh can run and so no-removal and no-other-tier can fail. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, routing, no-network]
max_turns: 20
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The clean skill is invoked and runs scan.sh and no other tier, without asking first; the reply reports reclaimable sizes; dist/bundle.js still exists and no removal command runs."
---

This repo has grown way past what the source code should take on disk. What's eating the space, and how much of it could I get back?
