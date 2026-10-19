---
description: "Phase-boundary review: a phase tagged `Review: code-design` gets `/review:quality-gate code-design` with the worktree, the previous boundary commit as base, the plan's quality bar and the report-only flag, before the phase-verifier and the boundary commit."
tags: [implement-dispatch, phase-boundary, review-tags, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The ordered step list invokes `/review:quality-gate code-design --worktree /srv/wt/shop-pricing --base 4b1d9e07c2a85f3e6d10b7a9c4e2f8d1a3b5c6e7 --quality-bar internal --report-only` first, then the phase-verifier, and the git commit of the phase only after both."
---

/implementation:implement-dispatch phase-3 Don't dispatch anything, don't read files and don't run commands. Phase 3's worker returns are verified and its build/test gate passed. Print, as a numbered list, every remaining step of this phase boundary in the order you would run it, each with its exact command or skill invocation, then stop.

The plan (approved, autonomous run, commit authority `orchestrator`). Its Brief's captured assumptions include the line `Quality bar: internal`. Phase 3 adds a pricing rules module and is beyond a mechanical change; its header reads:

```markdown
### Phase 3: Pricing rules module [TODO]
Review: code-design
```

Phase 3's assigned worktree is `/srv/wt/shop-pricing` on branch `feat/pricing-rules`, with its changes uncommitted. The previous phase-boundary commit, Phase 2's, is `4b1d9e07c2a85f3e6d10b7a9c4e2f8d1a3b5c6e7`. The plan has no push rule.
