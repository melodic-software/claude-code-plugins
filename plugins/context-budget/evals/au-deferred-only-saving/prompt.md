---
description: 'Narration: the finished attribution row (prefixDelta 0, deferredDelta -3000, comparable true) is given as data. audit SKILL.md lines 252-256: prefixDelta and deferredDelta are presented separately, and a deny that empties a deferred schema reduces request weight without changing the context-usage headline; lines 329-331: the deferred bucket is recurring request weight, never already-saved weight (engine.md lines 82-85). deltas-separate needs each bucket with its own figure; deferred-is-request-weight and headline-unchanged need words the prompt lacks; no-deferred-free fails a reply that calls the deferred weight already handled or cost-free.'
tags: [context-budget, audit, outcome, report-contract, deferred, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply gives the prefix delta (0) and the deferred delta (3,000) as two figures, says the saving is request weight sent with every request, says the context-usage headline does not move, and never calls the deferred pool cost-free or already handled.'
---

/context-budget:audit --tools NotebookEdit

That attribution run already finished on this machine. Its row for NotebookEdit shows prefixDelta 0 and deferredDelta -3000, comparable true. What does denying NotebookEdit save me?
