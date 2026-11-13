---
description: 'Legacy ship 6. Status on an integration-branch container whose sub-items are all closed with no PR yet, asked to wrap it up: the single integration PR from the recorded branch and the full gates come first, closed checkpoints are progress and not shipment, close-out runs at PR time, and the container closes only when the PR ships. integration-pr-from-branch reads the reply. Read-only tools, graded on the reply.'
tags: [ship, status, shared-branch, close-out, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Recognizes that in the shared-branch shape closed checkpoints record durable progress, not shipment, so the journey''s terminal step comes before any close-out: open the single integration PR from integration/330-schema-swap (/source-control:pull-request when installed, else the operator''s PR flow) and run the full verification gates. The container close-out (the decompose-owned ship ritual: close-out review against the container body, closing comment linking the shipping PR) runs at PR time, and the container closes only when that PR ships; the skill does not route a direct close-out, and does not close the container, while no integration PR exists.'
---

/work-items:ship #330

Item #330 is an open container item labeled spec-container. The container body carries `**Execution shape:** integration branch → single PR` and `**Integration branch:** integration/330-schema-swap`. The last sub-item was just closed; every sub-item is now closed. No PR exists from the integration branch. Wrap it up.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
