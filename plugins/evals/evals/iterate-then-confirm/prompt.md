---
description: "Hard case. Why hard: The flag combination is this plugin's guidance on a CLI the base model does not know; the blind base answers had no case flag and asked for 3 to 5 or 5+ runs to confirm. Self-reference: confirm-noise-report checks this plugin's own report."
tags: [local-defaults, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer gives `--case <name> --runs 1 --ablation none` for iteration, confirms at 3 runs per case, and reads the confirm run's noise report before trusting the change"
---

I'm adjusting one plugin eval case over and over to get its grader right. What's the cheapest way to re-run only that case while I iterate, and how many runs per case should I use before I believe a change actually helped? Answer in under 120 words.
