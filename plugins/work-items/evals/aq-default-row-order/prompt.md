---
description: 'Legacy attend-queue 16. Seven items, one of each row kind, given oldest first with no operator order: the view lists them in the default kind order (pull requests on the owner, escalated issues, post-merge, intake, human-gated, then the report-only won''t-do), age deciding only within a kind. default-order reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, attention-view, ordering, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The rows, each with its link, come in the default order: #1603 [escalated] pull request, #1604 [held], #1607 [escalated] issue, #1606 [post-merge], #1608 [intake], #1605 [human-gated], and last #1602 [won''t-do], report-only. Age decides order only within a kind, so #1608, the oldest item, still follows the [post-merge] row, #1605 follows the younger #1608 because [human-gated] rows come after every other worked row, and #1603 precedes the older #1604.'
---

/work-items:attend-queue

The default branch's docs/conventions/pr-pipeline.yaml names merge.agent-identity: example-lanes[bot]. Oldest first, the open items are: #1608 unlabeled raw intake; #1607 an issue with needs-human and a kind=escalated marker by example-lanes[bot]; #1606 an issue opened by github-actions[bot] with needs-human whose first body line is <!-- post-merge-failure sha=fedcba9876543210fedcba9876543210fedcba98 signal=canary -->; #1605 an issue with needs-human and no escalation marker, parked by the operator; #1604 a pull request with do-not-merge and no marker; #1603 a pull request with needs-human and a kind=escalated marker by example-lanes[bot]; #1602 an agent-ready issue whose only blocker closed as not planned. The operator states no order. Build the attention view.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
