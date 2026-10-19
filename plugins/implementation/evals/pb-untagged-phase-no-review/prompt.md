---
description: "Phase-boundary review control: a phase with no `Review:` line gets no `/review:quality-gate` call at its boundary; the phase-verifier still runs."
tags: [implement-dispatch, phase-boundary, review-tags, read-only, control]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The ordered step list has no `/review:quality-gate` invocation, and it dispatches the phase-verifier before the boundary commit."
---

/implementation:implement-dispatch phase-3 Don't dispatch anything, don't read files and don't run commands. Phase 3's worker returns are verified and its build/test gate passed. Print, as a numbered list, every remaining step of this phase boundary in the order you would run it, each with its exact command or skill invocation, then stop.

The plan (approved, autonomous run, commit authority `orchestrator`). Its Brief's captured assumptions include the line `Quality bar: internal`. Phase 3 adds a pricing rules module and is beyond a mechanical change; its header reads:

```markdown
### Phase 3: Pricing rules module [TODO]
Implements: Design › Contracts (pricing rule lookup).
```

Phase 3's assigned worktree is `/srv/wt/shop-pricing` on branch `feat/pricing-rules`, with its changes uncommitted. The previous phase-boundary commit, Phase 2's, is `4b1d9e07c2a85f3e6d10b7a9c4e2f8d1a3b5c6e7`. The plan has no push rule.
