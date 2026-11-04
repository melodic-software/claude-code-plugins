---
description: "Explainer not asked for, with the policy printing action offer and triggers files and risk-path, offers the digest in one sentence naming both triggers and writes no record, rates no risk and builds no page before the reader accepts"
tags: [review, explain-change]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The reply offers the digest of acme/storefront#77 in about one sentence that names the files and risk-path triggers and says the page would be a local file, then stops for the reader's answer: it writes no Why, Before and after, Risk map or File by file record, dispatches no checker agent, builds no page, and posts nothing"
---

/review:explain-change 77

The pull request is 77 of acme/storefront, and it was just reviewed. Nobody asked for an explainer.

This run has no GitHub access and no shell, so the reads and the policy check were done for you. The pull request's facts are saved in .claude-lane/pr/facts.json and its diff in .claude-lane/pr/pr.diff; use .claude-lane/pr as the run's directory and do not read the pull request again. The policy script printed:

```json
{"action": "offer", "triggers": ["files", "risk-path"], "medium": {"value": "file", "source": "user", "explicit": true, "report": ["medium: file (your setting)"]}, "facts": {"files": 4, "changed_lines": 21}}
```

Read only those files and post nothing.
