---
schema_version: "1.1"
name: no-color-any-value
description: "Regression guard (the model passes it without the plugin): NO_COLOR=0 still disables color, since the rule is presence and non-empty"
tags: [terminal, regression-guard]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says any non-empty NO_COLOR, 0 included, turns color off, with an explicit --color flag as the override"
---

My CLI `pkgsync` prints a colored summary table. A user has `NO_COLOR=0` in their environment and says
they still expect color, because 0 should mean "don't disable". How should `pkgsync` decide whether
to color its output? Give the rule as you'd implement it, in under 150 words.
