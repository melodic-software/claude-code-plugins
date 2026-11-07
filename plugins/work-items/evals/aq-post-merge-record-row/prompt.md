---
description: 'Legacy attend-queue 14. An open needs-human issue from github-actions[bot] whose first body line is a post-merge record marker lists as a [post-merge] row with its failing run, with no escalation marker needed and no last-pass state, and the lane only restates it. post-merge-row-and-run reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, post-merge, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: '#1401 lists as a [post-merge] row with its issue link and the failing run https://github.com/example/repo/actions/runs/7002/attempts/2, although no escalation marker is on it, because its first body line is a post-merge record marker and its author is the workflow identity. No last-pass state is read or written: the open record is what makes it a row. The lane restates the row and leaves fixing main and closing the record to the operator; it takes no claim, closes nothing, reverts nothing, and merges nothing.'
---

/work-items:attend-queue

Open issue #1401, opened by github-actions[bot], carries needs-human and no escalation marker comment. Its body's first line is <!-- babysit-merge-demotion sha=0123456789abcdef0123456789abcdef01234567 signal=schedule --> and a later line reads '- Failing run: https://github.com/example/repo/actions/runs/7002/attempts/2'. Build the attention view; the operator then reads the row.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
