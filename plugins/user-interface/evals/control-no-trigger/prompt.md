---
schema_version: "1.1"
name: control-no-trigger
description: "A non-interface Python question must not invoke the design skill"
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer names csv.DictReader and no Skill call reaches user-interface:design"
---

In Python, how do I read a CSV file into a list of dicts? Answer in under 80 words.
