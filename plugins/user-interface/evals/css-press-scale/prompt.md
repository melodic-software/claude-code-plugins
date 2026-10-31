---
schema_version: "1.1"
name: css-press-scale
description: "Happy path: Written from MB:plugins/user-interface/skills/write-css/reference/interaction.md:60-81. A pressable button scales to between 0.95 and 0.98 on :active. Head moves which controls take the scale to the motion concern and lets dense UI skip it; two checkout buttons are not dense, so both versions share the outcome."
tags: [web, interaction, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The buttons scale to between 0.95 and 0.98 on :active"
---

Write the CSS for the Pay and Cancel buttons on our checkout form, with hover, keyboard focus and
pressed states. Plain CSS. This run cannot write files, so put the CSS in your reply.
