---
description: "Hard case. Why hard: the base model pins the agent model at most, often by alias, and gates on the exit code; this plugin's CI rules pin both --model and --judge-model to full model IDs, pass --trust-plugin for the non-TTY job, and read the JSON beside the exit code."
tags: [plugin-eval, ci, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The command pins --model and --judge-model to full model IDs (no alias), passes --trust-plugin, and the reply says to read the JSON, not only the exit code"
---

How do I run my plugin's evals in GitHub Actions on every PR so a regression fails the build? Give me the command and the gotchas. Answer in under 150 words.
