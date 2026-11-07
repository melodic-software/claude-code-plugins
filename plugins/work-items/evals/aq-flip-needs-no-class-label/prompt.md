---
description: 'Legacy attend-queue 6. Two answered [escalated] issues, one with no class label and one with a structural class: each flips to agent-ready in one edit while claimed, with no class label stamped, asked for or changed. both-flip-no-class-gate reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, flip, class-label, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Works the rows one at a time. For each, after the claim, the restatement and the operator''s answer, it applies the autonomous-eligible role label (agent-ready) and removes the human-gated role label in one edit, while the claim is held. The missing class on #4400 and the structural class on #4401 do not block the flip: it neither stamps nor asks for a class label first, and does not ask to reclassify #4401. It writes no class label. Only provenance: untrusted or provenance: signal would have blocked the plain flip.'
---

/work-items:attend-queue

Two [escalated] issues carry needs-human and status:ready, each with an escalation comment authored by the tracker's write identity whose first line is <!-- work-items:escalation lane=work-loop kind=escalated -->. #4400 has no class label. #4401 carries a structural class label. This session's standing direction forbids writing class labels. For each, the operator's answer removes the human blocker.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
