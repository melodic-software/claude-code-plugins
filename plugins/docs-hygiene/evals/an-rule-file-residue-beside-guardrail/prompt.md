---
description: "Hard: one conventions page holds three noise shapes (a conversational aside to the requester, a bare PR back-reference given as the rationale, a ghost ref into a slice-scoped .work path) beside three lines that look like noise but are not: a credentials prohibition (hard-guardrail negation carve-out), a bare .work/handoffs/ concern root (exempt), and an open task-list item citing #123 (tracker carve-out). The run must flag the first three and leave the other three alone. Written from the before SKILL.md contract."
tags: [docs-hygiene, audit-noise, outcome, scaffold, hard]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite, Bash]
expected_outcome: "The reply flags the 'As you asked' line (delete the address), the 'See PR #45' line (delete or relocate to a Sources footer) and the .work/payments-retry-spike/PLAN.md path (promote, durable pointer, or strip), and does not flag the API-token prohibition, the bare .work/handoffs/ path, or the open task-list item; no file is edited."
---

I'm about to share docs/conventions/payments.md with the rest of the team. Go through it and tell me which lines are leftover clutter a future reader shouldn't have to wade through, and what to do about each one. Quote each line you flag. Don't edit the file; I'll make the changes myself.
