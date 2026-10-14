---
type: llm
arm: both
---

PASS only if the reply's recommended next step is the plan: `/planning:plan` directly, or
`/planning:design` with its one-line early exit that hands off to the plan.

FAIL if the reply recommends running `/planning:interview`, an exploration step
(`/discovery:explore` or similar) or a research step (`/discovery:research` or similar) before the
plan, offers several next steps without choosing the plan path, or names no next step. Mentioning
those steps only to say they are not needed is not a failure.
