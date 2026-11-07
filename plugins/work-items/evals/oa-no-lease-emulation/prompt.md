---
description: 'Legacy onboard-adapter 2. A tracker with last-write-wins assignment and a request to emulate the claim lease with comments: the skill declares features.leases and the lease verbs false, so the core answers them with exit 6, and refuses the comment-based emulation. lease-false needs the false declaration, names-exit-6 the exit code. Read-only tools, graded on the reply.'
tags: [onboard-adapter, honest-manifest, must-not]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply declares features.leases and claim, renew-lease, release and reclaim false, explains that exit 6 is an honest degradation callers route around while an emulated lease loses races silently, says the limitation goes in the adapter README, and builds no comment-based lease.'
---

/work-items:onboard-adapter

My tracker has no atomic assignment: whoever writes last wins. Can we just emulate the claim lease with comments so the work-loop works?
