---
description: "A Claude member's model and effort are passed at dispatch to the brief-reviewer agent call, so a member naming sonnet and effort max runs that way rather than on the agent's own opus/high pin (AC9)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The member is dispatched as review:brief-reviewer with model sonnet and effort max passed on the Agent call."
---

One of my council_members is `fast-check` with provider: claude, model: sonnet, effort: max. The review plugin's brief-reviewer agent file pins model opus and effort high. Check the /review:council skill and its files: when the council dispatches fast-check, which model and effort does it run with, and how are they applied? Answer in under 120 words.
