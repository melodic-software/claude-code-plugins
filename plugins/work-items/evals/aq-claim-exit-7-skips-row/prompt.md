---
description: 'Legacy attend-queue 5. Two attended sessions on one repository; the row claim on the oldest [escalated] row returns exit 7: the lane, having built the full view and run reclaim once, skips #712 with no write and no retry and moves to the next candidate, with no shard argument. skips-712 reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, claim, concurrency, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The binding resolves, so session-start reclaim runs once before the first row claim. The full merged view is built first: every row is read, and only rows this session holds are mutated. Before any comment, label or triage mutation on #712 the session claims it through the seam claim verb with a fully-qualified id (assignee + lease, the same protocol as /work-items:work). On exit 7 it reports #712 skipped: claimed by another session, does not retry #712, posts no interview question, writes no answer and flips no label, then advances to the next candidate in the view or reports that no unclaimed rows remain. A single-session run needs no extra argument.'
---

/work-items:attend-queue

Two attended terminals are running against the same repository. The tracker binding resolves (provider github). This session has built the merged attention view and is about to work the oldest [escalated] row (#712 "Webhook retries lack jitter"). The operator directs: work that row now.

When this session invokes the seam claim verb on #712, it returns exit 7: another attended session already holds the live lease on that item.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
