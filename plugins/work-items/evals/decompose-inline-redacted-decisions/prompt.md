---
description: 'Legacy decompose 10. Two phases resting on numbered decisions in a public repository: both bodies inline D4 with its Q/D ids, the Phase 2 body inlines D5 with its machine-specific path redacted, and no body names a memory-root path or points at PLAN.md instead of the decision. q2-d4-ids reads the reply for Q2 and D4 together. Read-only tools, graded on the reply.'
tags: [decompose, item-body, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Publishes one item per phase. Both bodies have a Decisions section inlining D4 (read only from the replica, the primary is write-hot) with Q2 and D4; the Phase 2 body also inlines D5 with /srv/build-07/exports/refunds.csv generalized or dropped. No body names .work/ or a <slug>/PLAN.md path or links PLAN.md in place of the decision; the Parent line ''PLAN Phase N, topic refund-export'' is allowed.'
---

/work-items:decompose

The topic is refund-export and its PLAN.md is approved and has two phases: Phase 1 builds the replica-backed refund query, Phase 2 writes the CSV export. Its decision log numbers Q2 (should the export read from the reporting replica?) answered by D4 (yes, read only from the replica, because the primary is write-hot), and D5 (the CSV is written to /srv/build-07/exports/refunds.csv on the build host). Both phases rest on D4; only Phase 2 rests on D5. The repository is public. Publish the breakdown as plain items with no spec container; I approve it in advance.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, and show each item body as it would be published.
