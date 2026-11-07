---
description: "Legacy reuse-or-replace 3. Adopting the incumbent HTTP client for a new service 'to stay consistent'. routes-pick-for-the-problem and incumbency-named are regex; declines-consistency-ratification (llm) quotes legacy expectations 1-3. Read-only."
tags: [discipline, reuse-or-replace, outcome, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Identifies a dependency selection outside this skill, declines to approve it on consistency grounds, and routes it to /discipline:pick-for-the-problem, where matching the incumbent is the incumbency sin."
---

/discipline:reuse-or-replace we already use one HTTP client everywhere, so I'll just add the same one to the new service to stay consistent.
