---
description: "Hard case. Why hard: The base model offers to write the cases itself; this plugin's design skill does not scaffold a plugin target but hands it to `claude plugin eval init`, which writes cases in the runner's own layout."
tags: [design, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer hands the plugin target to `claude plugin eval init`, which interviews for cases and graders and writes them in the runner's layout; it settles criteria first and says to read and approve every case input before it is written"
---

I want behavioral evals for my whole Claude Code plugin at ./plugins/notes, measured against a run without the plugin. Can you write the eval cases for me? Answer in under 150 words.
