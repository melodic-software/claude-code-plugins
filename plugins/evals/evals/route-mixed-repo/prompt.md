---
description: "Hard case. Why hard: The base model proposes one harness, or generic per-part harnesses; the two specific routes (`claude plugin eval` for the plugin, `/claude-api build-eval` for the service) are this plugin's route table."
tags: [routing, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The plugin part goes to `claude plugin eval` (scaffolded with /evals:design, run with /evals:plugin-eval), and the summarizer service goes to `/claude-api build-eval`"
---

This repo has a `.claude-plugin/plugin.json` with three skills, plus a `services/summarizer/` folder whose Python code calls the Anthropic Messages API to summarize meeting notes. I want evals covering the whole repo. What route should each part take? Answer in under 150 words.
