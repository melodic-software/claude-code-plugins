---
description: "Hard case. Why hard: The base model may know plugin layout, but not that the runner loads only plugins, nor that the fire check is a `tool_used` grader on `Skill`; the blind answers read the score delta or the trace instead."
tags: [target-routing, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says no: wrap the skill in a minimal `.claude-plugin/plugin.json` (or scaffold one with `claude plugin init review-notes`) and point the command at that, and tell whether it fired from a `tool_used` grader on Skill whose input_match names the skill"
---

I have a standalone skill folder, just `review-notes/SKILL.md`, not inside any plugin. I want to measure it against a no-skill baseline with `claude plugin eval`. Can I point the command straight at the folder, and how would I tell from the results whether the skill was even used? Answer in under 150 words.
