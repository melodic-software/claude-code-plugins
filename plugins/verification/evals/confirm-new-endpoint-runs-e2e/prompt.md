---
description: 'Legacy confirm 7. A new API endpoint matches the e2e-app-runtime category, so Stage 2 calls /testing:run-e2e, then persists an assertion-only manifest with verified_at_sha under .work/<slug>/verification/ with no machine-local capture path. The testing plugin is not loaded in a run, so the prompt narrates it installed and asks for the skill calls and the manifest, framed like the existing narration cases. calls-run-e2e, verified-at-sha, manifest-path and no-local-path grade the reply; manifest-assertions (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, e2e, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Lists a /testing:run-e2e call, then an assertion-only manifest carrying verified_at_sha: 4f2c9e1, persisted under .work/<slug>/verification/ and pasted to the PR body or issue, with no machine-local capture path in it.'
---

/verification:confirm outcome. I added a new endpoint to the API. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The testing plugin is installed: /testing:run-e2e resolves in this session. The change adds GET /api/orders/{id}/receipt in src/api/receipts.ts. The branch is feat/order-receipts at commit 4f2c9e1, the working tree is clean, and the approved acceptance criterion is that the endpoint returns the order's receipt as JSON. Assume /testing:run-e2e returns a passing drive of the endpoint with two screenshots and one network trace kept in its run directory. List every skill call you make with its exact arguments, then write the evidence manifest you persist and the path you persist it to, then stop.
