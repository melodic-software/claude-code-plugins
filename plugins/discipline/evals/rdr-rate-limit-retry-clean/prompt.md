---
description: "Legacy reason-dont-recite 2. An inherited retry policy whose purpose is stated (a downstream burst rate limit, backoff tuned against it). confirms-live-rationale (regex) and no-churn (llm, legacy expectations 1-3) check the audit confirms it rather than overturning it. Read-only."
tags: [discipline, reason-dont-recite, outcome, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Confirms the retry policy stands on a live rationale and reports clean, without proposing a change."
---

/discipline:reason-dont-recite check the retry policy we inherited. (It exists because the downstream API rate-limits bursts, and the current backoff was tuned against that limit.)
