---
description: 'Legacy confirm 4. The refactor criterion: behavior preserved, and a test that passed before and fails after is a behavior change to surface, never a pass. A failing test is a Stage 1 FAIL, so the run stops there with NEEDS WORK (SKILL.md 153), or reaches refactor.md''s NOT CONFIRMED or BEHAVIORAL CHANGE DETECTED. The legacy prompt was the bare `/verification:confirm refactor`; this case narrates a rename-and-extract refactor with one newly failing test. names-failing-test grades the failing test in the reply, verdict-not-preserved a NEEDS WORK, NOT CONFIRMED or BEHAVIORAL CHANGE DETECTED verdict, behavior-preserved (llm) legacy expectations 1 and 3 verbatim. Legacy expectation 2 (reads context/refactor.md) is graded in confirm-refactor-large-reshape-equivalence, whose Stage 1 passes.'
tags: [verification, confirm, narration, no-network, refactor, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Reports test_po_box_line as a test that passed before and fails now, a behavior change, and gives NEEDS WORK, NOT CONFIRMED or BEHAVIORAL CHANGE DETECTED rather than a pass.'
---

/verification:confirm refactor. Do not read the repository, launch, install or run anything; treat these as facts. The change extracts the address-formatting code from src/orders/ship.ts into a new src/orders/address.ts and renames formatAddr to formatAddress; no behavior change was intended. Before the change all 140 tests passed. After it, 139 pass and test_po_box_line fails: it expects `PO Box 12` and now gets `P.O. Box 12`. Build and lint pass. Write the refactor confirmation report, then stop.
