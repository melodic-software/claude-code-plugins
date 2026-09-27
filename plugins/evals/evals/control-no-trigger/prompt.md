---
description: A pytest question that must be answered without invoking any skill in this plugin
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: The answer names conftest.py and no Skill call is made
---

In pytest, how do I share one fixture across several test files without importing it in each file? Answer in under 100 words.
