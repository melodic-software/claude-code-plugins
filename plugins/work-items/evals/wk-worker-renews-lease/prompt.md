---
description: 'Legacy work 6. A long autonomous item: lease_comment_id goes into the dispatch brief, the worker renews the lease at phase boundaries and before the TTL, the orchestrator renews only after the worker returns, and nobody renews an expired lease. lease-comment-id reads the reply. Read-only tools, graded on the reply.'
tags: [work, lease]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run records lease_comment_id from the claim and enumerates it in the dispatch brief. The worker is the renew actor during the blocked wait (renew-lease at phase boundaries and before the TTL deadline with a margin, not branch pushes); the orchestrator renews only after the worker returns, and neither renews an already-expired lease (exit 7, recover with a fresh claim).'
---

/work-items:work

Run autonomously. The claimed item will take hours of commits with no extra issue comments before the PR opens.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
