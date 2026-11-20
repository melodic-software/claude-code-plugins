---
description: "Medium. protect §5 with a corrections stand-in loaded: a verified win that keeps a precomputed copy of a slow source (a fast path that copies a slow one) still gets its counter ceiling at the measured value, and when /corrections:codify is among the available skills its guardrail line hands codify the choice of mechanism, naming the call, and picks no test or generator itself. Read-only; protect does not run. Hard because the obvious answer is to name the guardrail yourself (generate the table from the source and add a drift test), which the changed section leaves to codify. Source: issue 17200's host step for issue 17172, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [protect, outcome, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The CEILING line proposes 1 for shipping-quotes, the measured value. The GUARDRAIL line names a /corrections:codify call for keeping the rates table in step with the carrier rate service, leaves the choice of mechanism to codify, does not say codify is unavailable, and the reply does not run codify."
---

We sped up shipping quotes in our checkout service. Each quote used to call the carrier's rate
service once per parcel; it now reads `rates_table.json`, a copy of the carrier's rate card we
precompute and commit, and calls the service only once per checkout to read the rate card's
version.

`/performance:verify` reported the goal MET on a counter: `shipping-quotes`, the carrier calls one
checkout makes, measured cold, went from 9 to 1, identical across every run. Correlation: unproven
(no field data yet).

Before we run /performance:protect on this win, I need to know what it would propose. Load the
`performance:protect` skill with the Skill tool to read its rules, but don't run it, research
online or run anything. Read its sections on the ceiling and on guardrails for fragile optimizations
(section 5), and tell me what it would propose for this win.

End your reply with exactly these two lines, filled in:

CEILING: <the ceiling protect would propose for shipping-quotes>
GUARDRAIL: <one line: what protect proposes to keep rates_table.json from going wrong>
