---
description: "Legacy reuse-or-replace 4. A new endpoint reuses the established pagination and error shape, and its one divergence is recorded in an ADR. reports-clean (regex) and no-fabricated-finding (llm, legacy expectations 1-3) check a clean result. The workspace is empty, so the prompt asks the run to take its description as the state of the work. Read-only."
tags: [discipline, reuse-or-replace, outcome, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reports clean: the endpoint reuses the established way and its divergence carries an ADR-level rationale."
---

/discipline:reuse-or-replace the new endpoint follows the same pagination and error shape as the others, and where it differs it's noted in the ADR.

(The endpoint, the other endpoints and the ADR are in a checkout this session cannot open; take this description as the state of the work.)
