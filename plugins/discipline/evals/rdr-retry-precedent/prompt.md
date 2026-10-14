---
description: "A new card-charge handler retries three times only because every handler does. The run must name the precedent-only justification, re-derive the retry's purpose to find the double-charge risk, and confirm the convention still holds for the idempotent read handlers"
tags: [discipline, reason-dont-recite, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit]
expected_outcome: "Names the precedent-only justification, flags that retrying a non-idempotent charge can double-charge, and confirms withRetry stays valid for getUser and listOrders rather than rejecting the convention outright."
---

/discipline:reason-dont-recite the retry decision for chargeCard in notes/decision.md
