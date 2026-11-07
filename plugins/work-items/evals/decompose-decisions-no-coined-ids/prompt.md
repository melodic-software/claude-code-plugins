---
description: 'Legacy decompose 11. Decisions read from the PLAN.md gate-passed table and the interview ledger''s answered row: the item inlines D4 and Q2 with their ids and the id-less column-order row with no coined id, naming no memory-root path. q2-csv reads the reply for the Q2 id beside the CSV answer. Read-only tools, graded on the reply.'
tags: [decompose, item-body, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Publishes one item whose Decisions section inlines the replica decision as D4, the CSV-not-XLSX answer as Q2, and the column-order decision with no id, since its source row has none; no body names .work/, a <slug>/PLAN.md path or interview-checklist.md.'
---

/work-items:decompose

The topic is refund-export. Its approved PLAN.md has one phase, Phase 1: the CSV refund export. The prompt names no decisions; read them from the plan. PLAN.md's `Decisions made (gate-passed)` table has two rows: `D4 | Read refunds only from the reporting replica | Phase 1 queries the replica | primary is write-hot | plan` and, with no id, `Columns follow the finance team template | Phase 1 fixes the column order | finance template doc | plan`. The topic's interview-checklist.md register has one answered row, `Q2 | answered | round 1 | Export format? | CSV, not XLSX`. The repository is public. Publish the breakdown as one plain item with no spec container; I approve it in advance.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, and show the item body as it would be published.
