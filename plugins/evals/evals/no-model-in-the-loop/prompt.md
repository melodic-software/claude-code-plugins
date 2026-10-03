---
description: "Routine guard (regression-guard). Says LLM eval design does not apply to a tool with no model in it, and stops. Expect 1.00 in both arms (both blind best-guess answers pass)."
tags: [routing, routine, regression-guard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says LLM eval design does not apply because nothing in the tool calls a model, and stops; ordinary tests are fine to mention"
---

My manager wants 'LLM evals' added to our repo. It's a Go command-line tool that parses CSV files, and nothing in it calls any model. How should we set those evals up? Answer in under 100 words.
