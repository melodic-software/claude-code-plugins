---
description: "Near-miss negative control: Near miss on the evals.json format, which every evals description routes away from; measures a description boundary. No evals skill should fire."
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says `expectations` should be an array of strings, and none of evals:methodology, evals:plugin-eval, or evals:validate is invoked"
---

This is my skill's evals/evals.json for Anthropic's skill-creator plugin. Is anything structurally off before I use it?

```json
{"skill_name": "deploy-notes", "evals": [{"id": 1, "prompt": "Summarize the deploy notes", "expected_output": "A three-line summary", "expectations": "Names the release"}]}
```

Answer in under 100 words.
