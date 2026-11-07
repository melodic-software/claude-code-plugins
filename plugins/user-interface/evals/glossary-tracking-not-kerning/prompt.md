---
schema_version: "1.1"
name: glossary-tracking-not-kerning
description: "Routine: the feel request becomes tracking, scoped to the uppercase labels."
tags: [glossary, near-synonym, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply answers tracking, says it is not kerning and why, and scopes the change to the uppercase labels"
---

The uppercase section labels in our sidebar look cramped, every letter is jammed against the next one. What do I ask for? Is that a kerning fix?
