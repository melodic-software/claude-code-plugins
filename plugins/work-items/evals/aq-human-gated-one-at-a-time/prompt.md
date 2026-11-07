---
description: 'Legacy attend-queue 17. Three parked needs-human issues and nothing else waiting: the lane states the count, offers the oldest alone with its restatement, moves to the next only after an answer or skip, and keeps needs-human on each whose answer still needs a person, recording the answer as a comment. states-count reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, human-gated, one-at-a-time, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Lists the three items as [human-gated] rows and states the count, 3. Then offers only #1201, the oldest: claims it, restates the item, that it waits on a secret only the owner holds, and the options presented, and asks. It does not put #1202 or #1203 in the same question. Only after #1201''s answer is written back as a comment does it offer #1202 alone, with its own restatement (a retention period with no recommendation), and after the operator skips #1202 it offers #1203 alone. Each item that still meets the label test keeps needs-human, with the answer and its completion route recorded as a comment; none is flipped to agent-ready.'
---

/work-items:attend-queue

The escalated rows are done and no intake is waiting. Three open issues still wear needs-human with no escalation marker, oldest first: #1201 'Rotate the deploy key for the docs site' (its brief says the key is held only by the owner), #1202 'Pick the retention period for audit logs' (its brief lists 30 and 90 days with no recommendation), and #1203 'Drop the legacy export endpoint' (its brief says removing it breaks two external consumers with no rollback). The operator says: go through them.

The operator's answers, in the order the rows are offered: on #1201, "I'll rotate it myself on Friday; keep it with me"; on #1202, "skip it, I need to ask legal first"; on #1203, "keep it parked until I have talked to both consumers".

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
