---
description: "Hard case. Why hard: the base model either prices the pass well under 1 USD or stops to ask before starting; this plugin prices a fresh suite at about 0.2 USD per run (24 runs, roughly 4.8 USD) and says a pass under the ceiling starts with --max-cost-usd and no confirmation. Bash is not granted, so the reply is the only evidence."
tags: [plugin-eval, cost, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply prints a USD estimate of roughly 4.8 (3 to 4.99), says the pass goes through under the 5 USD ceiling with --max-cost-usd 5, and does not ask for confirmation"
---

My notes plugin has an eval suite: 4 cases, the default 3 runs, the normal with-and-without pass, read-only tools, regex graders only. My spending ceiling is 5 USD. Will a full pass fit under it? If it does, go ahead. I'm away from my terminal, so just tell me the estimate and the exact command you'd start. Answer in under 120 words.
