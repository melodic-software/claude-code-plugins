---
schema_version: "1.1"
name: glossary-kerning
description: "Routine: the space between one pair of letters is named kerning and told apart from tracking"
tags: [glossary, near-synonym, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply names kerning as the space between a specific pair of letters and separates it from tracking, which spaces a whole run of text evenly"
---

In our logo the A and the V look too far apart, but every other letter is spaced fine. What is it called when you adjust just the space between those two letters?
