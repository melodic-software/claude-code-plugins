---
description: 'Legacy evidence-loop-03 (narration). A capture that could not run reads `Capture: blocked (<reason>)` and is not by itself a NEEDS WORK; the unobserved download makes the verdict NOT VERIFIED and the count stays 0 (SKILL.md Capture status; Evidence loop table). The prompt is the legacy one. capture-line, loop-line, verdict-not-verified grade the reply; blocked-not-gap (llm) legacy expectation 2 verbatim.'
tags: [verification, confirm, narration, no-network, evidence-loop, capture, unattended, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Capture: blocked (no usable driver: playwright-cli not installed), count 0; the verdict is NOT VERIFIED, not NEEDS WORK; Evidence loop: 0/3.'
---

/verification:confirm outcome --unattended. Do not read the repository or run anything; treat these as facts. The current branch is feat/export-csv, the working tree is clean, and the evidence-loop file holds count 0. Stage 1 already passed. The change adds a CSV export button; AC1 is that the button downloads the visible rows, and a unit test added in the diff checks the CSV builder's output against the example rows AC1 states. /testing:run-e2e ran and wrote e2e-summary.json with capture {"status": "blocked", "reason": "no usable driver: playwright-cli not installed", "count": 0}. Write the verdict with its Capture and Evidence loop lines, then stop.
