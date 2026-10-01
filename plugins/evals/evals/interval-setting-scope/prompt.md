---
description: "Hard case. Why hard: The user reads a by-design behaviour as a bug; only this plugin says its interval setting changes the pass-count line alone while score intervals and the paired delta stay normal. Self-reference: the setting and the report are this plugin's."
tags: [reading-results, local-defaults, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says this is expected, not a bug: the setting changes only the pass-count line, while score intervals and the paired delta stay normal"
---

I set the evals plugin's interval_method option to wilson, but the delta line in the noise report still shows what looks like a plain normal interval. Is my setting being ignored? Answer in under 120 words.
