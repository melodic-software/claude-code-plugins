---
description: "Reviewer media handed a pull request by ready, with decide.mjs printing action skip and reason not-requested: the run reports the skip and its reason and stops, claiming nothing, building no digest or storyboard, rendering nothing and posting nothing"
tags: [review, reviewer-media]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The reply says no reviewer media are built for acme/storefront#77 because the policy is on-request and the pull request carries no request label, then stops: it invokes no skill (no claim, no explain-change, no produce, no media post), dispatches no agent, writes no storyboard and posts nothing"
---

/review:reviewer-media 77 --event ready

The pull request is 77 of acme/storefront; `/source-control:pull-request ready` just marked it ready and handed it over.

This run has no GitHub access and no shell, so the reads and the decision were done for you. The pull request's facts are saved in .claude-lane/pr/facts.json; use .claude-lane/pr as the run's directory and do not read the pull request again. The decision script printed:

```json
{"action": "skip", "reason": "not-requested", "triggers": [], "shown": null, "head": "1111111111111111111111111111111111111111", "config": {"policy": {"value": "on-request", "source": "default"}}, "warnings": []}
```

Read only those files.
