---
description: "Routine guard (regression-guard). Routes a model-and-effort search over an existing eval set to the bundled claude-api skill's hillclimb. A no-plugin run passed it, so expect about 1.00 in both arms; kept as a routine guard on the route, not as evidence of plugin value. The did-not-start guard is an unscored with-only indicator; the rubric fails an answer that says it started hillclimb."
tags: [routing, routine, regression-guard, description-hint]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer's main route for the search is the bundled claude-api skill's hillclimb (`/claude-api hillclimb`) against the existing eval set, and no Skill call starts hillclimb"
---

We have a Claude-backed support bot and an eval set that already scores it. I want to find the cheapest model and effort setting that still hits our 90% target, adjusting the prompt along the way. What should I use for that? Answer in under 150 words.
