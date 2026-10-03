---
description: "Hard case. Why hard: The base model pins the agent model at most, often by alias; the non-TTY trust refusal, pinning the judge as well, by full model ID, and the overloaded exit codes are this plugin's CI rules."
tags: [ci, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The command passes `--trust-plugin` and pins both `--model` and `--judge-model` by full model ID, not an alias; the answer says pinning both keeps a model rollout from reading as a plugin regression, and that the job reads the JSON as well as the exit code"
---

I want a GitHub Actions job that runs `claude plugin eval` on my plugin for every PR and fails the PR when the suite regresses. Give me the command the job should run and anything that's easy to get wrong. Answer in under 150 words.
