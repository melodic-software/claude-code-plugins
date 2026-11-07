---
description: 'Legacy attend-queue 2. An [escalated] row and an [intake] row worked in one pass: the lane claims the escalated row, interviews, writes the answer back as a comment, flips it in one edit while claimed and clears @me; the intake row goes to /work-items:triage under its interactive gate; comments carry the AI disclaimer from the per-user layer. disclaimer-true reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, escalation, flip, disclaimer, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'For #720 the session acquires the seam claim (assignee + lease) before any comment or label change. It drives the decision via /planning:interview when the planning plugin is installed (inline focused questions, one at a time, as the fallback) and writes the answer back as an issue comment on the item, then flips it in one edit while the claim is held: the autonomous-eligible role label applied and the human-gated role label removed, both resolved from config.role_labels, then @me cleared via the adapter assignee edit and the lease released. The item re-enters the worker loop''s frontier; this lane never dispatches or executes it. For #721 the lane takes no claim itself: /work-items:triage claims it and runs under its interactive direction gate, recommendation first, mutation only after the operator''s direction. ai_disclaimer resolves true from the per-user layer, so agent-authored comments carry the AI disclaimer. Nothing is merged.'
---

/work-items:attend-queue

The operator works two rows: an [escalated] item, #720 "Export API returns two response shapes", where the worker asked which of two API shapes to keep, (a) a cursor-paginated object or (b) a bare array; and an [intake] bug report, #721 "Search crashes on an empty query". The operator answers the API question: keep (a), the cursor-paginated object. On the bug, the operator directs triage to go with its recommendation. The per-user ai_disclaimer is true and the repository has no docs/conventions/work-items.yaml.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
