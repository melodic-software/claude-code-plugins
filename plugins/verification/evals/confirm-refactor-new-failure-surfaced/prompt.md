---
description: 'Legacy confirm 4. The refactor criterion: behavior preserved, read from context/refactor.md, and a test that passed before and fails after is a behavior change to surface, never a pass. The legacy prompt was the bare `/verification:confirm refactor`; this case narrates a rename-and-extract refactor with one newly failing test. reads-refactor-context grades the Read (with-only), names-failing-test the failing test in the reply, verdict-not-preserved a NOT CONFIRMED or BEHAVIORAL CHANGE DETECTED verdict (refactor.md section 7), behavior-preserved (llm) legacy expectations 1 and 3 verbatim.'
tags: [verification, confirm, narration, no-network, refactor, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Reads context/refactor.md, reports test_po_box_line as a test that passed before and fails now, and gives NOT CONFIRMED or BEHAVIORAL CHANGE DETECTED rather than a pass.'
---

/verification:confirm refactor. Do not read the repository, launch, install or run anything; treat these as facts. The change extracts the address-formatting code from src/orders/ship.ts into a new src/orders/address.ts and renames formatAddr to formatAddress; no behavior change was intended. Before the change all 140 tests passed. After it, 139 pass and test_po_box_line fails: it expects `PO Box 12` and now gets `P.O. Box 12`. Build and lint pass. Write the refactor confirmation report, then stop.
