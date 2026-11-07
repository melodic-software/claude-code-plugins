---
description: 'Legacy attend-queue 11. An escalated pull request on a provider whose item listing returns issues only: the lane also runs the pull-request listing, lists #980 as [escalated], comments the answer on it, removes only the human-gated label, and applies no agent-ready or class label and no merge. pr-listing reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, pull-request, escalation, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The view lists pull request #980 as an [escalated] row, found by also listing open pull requests that carry the human-gated label through the adapter''s pull-request listing, since the issue listing alone would miss it. After the brief-before-ask restatement and the operator''s answer, the answer is written back as a comment on #980 and the human-gated role label is removed. No autonomous-eligible role label and no class label is applied to the pull request, its body is left alone, and the lane does not merge it.'
---

/work-items:attend-queue

The bound provider is github; its item listing returns issues only. Open pull request #980 wears needs-human and carries a comment by example-lanes[bot], the repository's merge.agent-identity, whose first line is <!-- work-items:escalation lane=pr-unblock kind=escalated --> asking whether to keep or drop a failing migration step. No open issue carries needs-human. Build the attention view; the operator then answers: drop the step, and the lane may resume.

Treat the state above as what this run's reads return, and the operator's answer as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
