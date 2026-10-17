---
description: "A request whose goal cannot be inferred. The reply asks one batch of questions about what the result is for before raising anything, and does no work."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "One batch of clarifying questions about the goal behind the request, no raised version yet, and no Write, Edit or Bash call."
---

/discipline:be-ambitious Help me with my newsletter.
