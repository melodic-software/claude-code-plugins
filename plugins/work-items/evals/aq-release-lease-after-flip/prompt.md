---
description: 'Legacy attend-queue 7. After an answer removes the blocker on a claimed [escalated] row: flip in one edit while claimed, clear @me through the adapter, then end the lease with the seam release verb and the claim''s lease_comment_id rather than leaving it to its TTL or hand-writing lease JSON. release-with-lease-id reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, lease, release, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'While still holding the claim, the session applies the autonomous-eligible role label and removes the human-gated one in a single edit, then clears @me through the adapter''s assignee edit, then runs the seam release verb, work-item-tracker.sh release "github:<owner>/<repo>#3711" --lease-comment-id 5858800001. It does not leave the lease to run out its TTL, because claim backs off from any earlier live lease, the same login''s included. It reads exit 0 with either released value as done, and never hand-writes lease-comment JSON.'
---

/work-items:attend-queue

The operator answers the [escalated] question on #3711, which removes the human blocker. This session claimed the row through the seam at the start of the row; the claim object carried lease_comment_id 5858800001 under a 24-hour binding TTL. The bound provider is github, whose manifest declares release: true. A worker lane running as the same GitHub login will look for work on its next cycle.

Treat the state above as what this run's reads return, and the operator's answer as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
