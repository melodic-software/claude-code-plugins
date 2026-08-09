---
outcome: early-exit
tier: A
resolved_by: /planning:interview rounds 3–5
---

# Design resolution — docker-sandbox-substrate

## Tier

**A — design-significant.** Criteria 3–7 add contract vocabulary (a verification-topology axis set),
additive keys on an agent-unwritable schema, new checker predicates, and a new plugin `userConfig`
surface. That is a contract change across four components.

## Why `/planning:design` is not re-run

The design threads a Tier A gate exists to force were explored and RESOLVED by `/planning:interview`
rounds 3–5, whose register gated clean (`registered=23 open=0 deferred=4 blocked=0 withdrawn=5
answered=14 brief=ok status=clean`). Each thread below names its resolving question; the register and
its evidence live in the topic's memory slice.

| Design thread | Resolved by | Resolution |
|---|---|---|
| Where verification policy lives (module boundary) | Q16 | SPLIT — per-class floors on the agent-unwritable security binding; lens selection and the advisory lane in plugin `userConfig` |
| Verifier-policy vocabulary (the type surface) | Q17 | Roles + relational constraints + machine-checkable predicates (Axes A–E). Capability labels rejected with sourced reasons |
| Topology shape (new mechanism vs existing seam) | Q13 refined | A column on the existing guardrail matrix, not new machinery |
| Aggregation semantics | Q19 | Unanimous to auto-proceed; any dissent routes to a human. Deliberation barred as a fixed invariant |
| Escalation shape | Q18 | Fixed per-class floor plus disagreement-triggered escalation above it |
| Visual-lane placement | Q14 | Advisory only, downstream of deterministic detection |
| Orchestrator/framework selection | Q12 | None adopted; thin pipeline code against the existing provider seam |
| Probe assertion set | Q6 | A third assertion covering the workspace mount, generalizing to every substrate class |

## What remains open at plan time

- **Q20** — the exact FORM of the workspace assertion and the data-flow rewording of the egress
  assertion. Arbiter is `/planning:plan`; resolved in the PLAN body, not here.
- **Q21 / Q22 / Q23** — USER-RESERVED. Parked; none of criteria 3–7 depends on them.

## Override

If the design threads above are judged insufficiently resolved, the correction is to run
`/planning:design` before implementation — not to widen the plan.
