---
schema_version: "1.1"
name: css-control-no-trigger
description: "A pure visual-direction request with no CSS to write must not invoke write-css"
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer gives a mood, a palette described in words and a typeface pairing, and no Skill call reaches user-interface:write-css"
---

Suggest a brand direction for a meditation app: the mood, a color palette described in words, and a typeface pairing. No code, under 120 words.
