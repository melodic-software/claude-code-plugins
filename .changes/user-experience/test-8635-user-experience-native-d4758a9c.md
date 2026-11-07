---
bump: patch
---

### Changed

- The evaluate, plan-user-research and synthesize `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Fifteen new cases cover measure selection without instrumenting, the fresh-context evaluator for a same-session flow, the three live-app checks (fold visibility, ambiguous copy, in-product pictures), a screener that recruits no one, method choice with `Basis:`, facilitator guides, proto-personas, synthetic users as hypotheses, both jobs-to-be-done schools, participant privacy, and three cases where no skill should fire. `fires-evaluate`, `uc12-legacy-redesign`, `uc2-plan-interviews` and `uc7-tickets-and-survey` gain graders for the legacy expectations they did not yet grade. Legacy evaluate 1 was already covered by `uc9-cancel-flow`. Legacy plan-user-research 5 and synthesize 6 are held on #8635 for an owner decision on their graders.
