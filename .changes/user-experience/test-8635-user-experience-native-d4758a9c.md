---
bump: patch
---

### Changed

- The evaluate, plan-user-research and synthesize `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Seventeen new cases cover measure selection without instrumenting, the fresh-context evaluator for a same-session flow, the three live-app checks (fold visibility, ambiguous copy, in-product pictures), screeners and plans that recruit no one, method choice with `Basis:`, facilitator guides, inclusive-research plans, proto-personas, synthetic users as hypotheses, both jobs-to-be-done schools, participant privacy, an embedded ticket instruction, and three cases where no skill should fire. `fires-evaluate`, `uc12-legacy-redesign`, `uc2-plan-interviews` and `uc7-tickets-and-survey` gain graders for the legacy expectations they did not yet grade. Legacy evaluate 1 was already covered by `uc9-cancel-flow`.
