---
description: 'Legacy evidence-loop-01 (narration). A NEEDS WORK verdict on a new head at count 2 raises it to 3, writes the file atomically (a .tmp in the same directory, then mv over it), the manifest line reads `Evidence loop: 3/3`, and Next sends AC2 back to implementation (SKILL.md Evidence loop). The prompt is the legacy one, which already framed itself as narration. loop-line, atomic-write grade the reply; loop-back (llm) legacy expectations 1 and 4 verbatim.'
tags: [verification, confirm, narration, no-network, evidence-loop, unattended, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The file gets a c3 NEEDS WORK entry with count 3, written to evidence-loop.feat-cart-tax.json.tmp in the same directory and renamed over the file; the manifest line reads Evidence loop: 3/3; Next says to fix AC2 and run /verification:confirm again.'
---

/verification:confirm outcome --unattended. Do not read the repository or run anything; treat these as facts. The current branch is feat/cart-tax and the working tree is clean. Stage 1 already passed. .work/cart-tax/verification/evidence-loop.feat-cart-tax.json holds {"cap": 3, "count": 2, "heads": [{"sha": "a1", "verdict": "NEEDS WORK", "at": "2026-10-30T10:00:00Z"}, {"sha": "b2", "verdict": "NEEDS WORK", "at": "2026-10-31T10:00:00Z"}]}. The head under verification is c3. The fresh-context verifier's verdict is NEEDS WORK: AC2, tax on discounted items, is MISSING. Write the evidence-loop file update you make, the manifest's Evidence loop line, and the report's Next section, then stop.
