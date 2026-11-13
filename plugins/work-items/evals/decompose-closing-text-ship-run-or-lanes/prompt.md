---
description: 'After publishing a spec container and its items, the decompose report closes with how they run: /work-items:ship run on the container at the keyboard, otherwise the agent-ready items left for the lanes. ship-run reads the reply for the command. Read-only tools, graded on the reply.'
tags: [decompose, report]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Publishes the container and three items, then reports the count, the dependency order and AFK versus HITL, and closes with: at the keyboard, /work-items:ship run on the container; otherwise the agent-ready items stay for the lanes.'
---

/work-items:decompose

The topic is usage-billing. Its approved PLAN.md has a `## Brief` and three phases: Phase 1 adds the metering table, Phase 2 the nightly rollup (blocked by Phase 1), Phase 3 a pricing-page review a person must sign off. The binding is GitHub and its `config.container_label` is `spec-map`. When you present the breakdown, the operator answers: approve the items as drafted; yes, publish the spec container; per-item PRs. The container is created as https://example.com/o/r/issues/900.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and show the final report.
