---
description: "Near-miss negative control: Near miss on the 'LLM judge' and 'grading rubric' triggers: a DeepEval GEval API question that belongs to DeepEval's docs. No evals skill should fire."
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer constructs a `GEval(...)` metric, and no evals skill is invoked"
---

In DeepEval, how do I set up a GEval metric with my own grading criteria so an LLM judge scores whether the answer is correct? Show the Python. Answer in under 120 words.
