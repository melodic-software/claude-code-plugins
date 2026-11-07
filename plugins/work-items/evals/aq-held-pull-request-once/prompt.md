---
description: 'Legacy attend-queue 12. Four held or escalated pull requests: do-not-merge and unmarked needs-human pull requests list as [held] with the holding label, the trusted-marker needs-human one lists once as [escalated], an old marker without needs-human does not hide a held one, and the [held] row is only restated. held-and-1203-escalated reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, pull-request, held, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: '#1201, #1202 and #1204 list as [held] rows, found through the pull-request listing, each naming the label that holds it (do-not-merge for #1201 and #1204, the human-gated role label for #1202) with its link. #1203 lists once, as [escalated], because its trusted marker and human-gated label make it an [escalated] row, which keeps it out of [held]. #1204''s old marker does not hide it: without the human-gated label it is no [escalated] row. For #1201 the lane restates the row and leaves the next step to the operator: it takes no claim, removes no label, and does not merge.'
---

/work-items:attend-queue

The bound provider is github; its item listing returns issues only. The default branch's docs/conventions/pr-pipeline.yaml names merge.agent-identity: example-lanes[bot]. Open pull requests: #1201 carries do-not-merge and no escalation marker; #1202 carries needs-human and no escalation marker; #1203 carries needs-human and a comment by example-lanes[bot] whose first line is <!-- work-items:escalation lane=pr-unblock kind=escalated -->; #1204 carries do-not-merge, no needs-human, and an older comment by example-lanes[bot] with the same marker, left from an escalation the operator already answered. Build the attention view; the operator then reads the #1201 row.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
