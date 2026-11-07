---
description: 'Legacy evidence-loop-02 (narration). At count 3 a NEEDS WORK on a rebased head starts no loop-back: count stays 3, d4 is recorded through a .tmp and a rename, the line reads `Evidence loop: 3/3 cap reached, last NEEDS WORK`, and Next routes to opening the pull request so the pipeline''s park-and-retry takes over (SKILL.md Evidence loop table). The prompt is the legacy one. cap-line, routes-pr grade the reply; no-loop-back (llm) legacy expectations 1, 2 and 4 verbatim.'
tags: [verification, confirm, narration, no-network, evidence-loop, unattended, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'No loop-back to implementation; d4 recorded as NEEDS WORK with count 3 via a temporary file and rename; Evidence loop: 3/3 cap reached, last NEEDS WORK; Next routes to /source-control:pull-request and the pipeline''s park-and-retry path.'
---

/verification:confirm outcome --unattended. Do not read the repository or run anything; treat these as facts. The current branch is feat/cart-tax and the working tree is clean. Stage 1 already passed. .work/cart-tax/verification/evidence-loop.feat-cart-tax.json holds {"cap": 3, "count": 3, "heads": [{"sha": "a1", "verdict": "NEEDS WORK", "at": "2026-10-29T10:00:00Z"}, {"sha": "b2", "verdict": "NEEDS WORK", "at": "2026-10-30T10:00:00Z"}, {"sha": "c3", "verdict": "NEEDS WORK", "at": "2026-10-31T10:00:00Z"}]}. The head under verification is d4, a rebase of c3 onto a newer main with no other change. The fresh-context verifier's verdict is NEEDS WORK: AC2 is still MISSING. Write the evidence-loop file update you make, the manifest's Evidence loop line, and the report's Next section, then stop.
