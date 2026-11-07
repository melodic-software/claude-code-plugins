---
schema_version: "1.1"
name: design-animation-review-routes-audit
description: "Reviewing existing animation is the animation-audit concern, whose first route is /user-interface:audit; the request may fire audit directly, so the judge reads the trace for either a Skill call to audit or a reply that routes there."
tags: [design, routing, audit]
runs: 3
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The run invokes user-interface:audit, or the reply routes the review to /user-interface:audit or the animation-audit concern"
---

Can you check whether the animations we added in this branch are any good?
