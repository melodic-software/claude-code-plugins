---
description: 'Legacy attend-queue 13. A work-resolve-issue hand-back with needs-human and a trusted marker lists as an ordinary [escalated] row with its run link, and a usage-limit stop that kept agent-ready lists nowhere. run-link reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, issue-lane, hand-back, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: '#1301 lists as an [escalated] row with its issue link and the run link https://github.com/example/repo/actions/runs/7001 its hand-back comment carries; the lane adds no separate hand-back row kind. #1302 is not listed: a usage-limit stop keeps the autonomous-eligible label and adds no human-gated label, so the issue lane restarts it.'
---

/work-items:attend-queue

The default branch's docs/conventions/pr-pipeline.yaml names merge.agent-identity: example-lanes[bot]. #1301 carries needs-human and a comment by example-lanes[bot] whose first line is <!-- work-items:escalation lane=work-resolve-issue kind=escalated --> and whose text says the run stopped partway and links https://github.com/example/repo/actions/runs/7001. #1302 carries agent-ready and no needs-human, and a comment by example-lanes[bot] saying the work-resolve-issue lane stopped on its usage limit and restarts after the reset. Build the attention view.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
