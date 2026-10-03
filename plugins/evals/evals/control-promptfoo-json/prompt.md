---
description: "Near-miss negative control: Near miss on the 'LLM eval' triggers: a promptfoo assertion question that belongs to promptfoo's docs. No evals skill should fire."
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer names the `is-json` assertion type, and no evals skill is invoked"
---

In promptfoo, how do I assert in my config that the model's output is valid JSON? Answer in under 80 words.
