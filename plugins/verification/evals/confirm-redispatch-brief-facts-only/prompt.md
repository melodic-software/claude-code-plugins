---
description: 'A fresh verifier returned NEEDS WORK on a scope doubt with "Recommended: accept the edit". The producer writes the brief for a new fresh verifier that adds only facts, the scope rule quoted from the PLAN.md Brief with its source named, and carries no wanted verdict and none of the earlier recommendation (SKILL.md "Independence of the verdict"). Every grader reads the written brief file.'
tags: [verification, confirm, narration, no-network, verifier, independence, unattended]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: '.work/redispatch-brief.md quotes the scope rule from the PLAN.md Brief and names that source, and holds no recommendation ("accept the edit", "Recommended") and no wanted verdict ("CONFIRMED" as the outcome, "should pass", "expected verdict").'
---

/verification:confirm outcome --unattended. Do not read the repository; treat these as facts. The current branch is feat/order-notes, the working tree is clean, HEAD is 4f1c2a9e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e, and the evidence-loop file holds count 0. Stage 1 already passed, and the verification level resolved standard. The change lets a customer attach a note to an order, and its PLAN.md Brief lists four acceptance criteria. The Brief's Constraints section says: "Scope: src/orders/notes/ and tests/orders/, including edits to existing order tests that exercise the note limit."

You already dispatched a fresh-context verifier with the criteria, the diff and the evidence directory, and recorded its verdict. It returned: verdict NEEDS WORK; criteria 1 to 3 COMPLETE; criterion 4 (the order-notes endpoint rejects a note over 500 characters) PARTIAL, because the diff also edits tests/orders/test_note_limits.py and no source it was given says that file is in scope; open question: "Is the edit to test_note_limits.py in scope? Recommended: accept the edit."

You will dispatch a new fresh-context verifier on this head. Write the full brief for it to .work/redispatch-brief.md with the Write tool. Do not dispatch it or any other agent, and do not record a verdict. Then stop.
