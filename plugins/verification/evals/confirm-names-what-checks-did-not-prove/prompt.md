---
description: "The only test is a self-authored tautology and punctuation stripping has no test, so the report names both criteria under 'Not proved by these checks'"
tags: [confirm, evidence-ranking]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Reports a 'Not proved by these checks' section that lists AC2 (punctuation stripping, no check exercises it) and AC1 (its only test is self-authored and compares slugify's output with itself), and does not report the change as CONFIRMED"
---

/verification:confirm
