---
schema_version: "1.1"
name: css-rule-color
description: "Hard (palettes are usually written in hex and rgba): colors are written in oklch() and derived with color-mix in oklch"
tags: [always-on-rule, rule-color, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The palette is written in oklch() (with none as the hue of grays), and the hover shade and translucent tint are derived with color-mix(in oklch, ...)"
---

Write CSS custom properties for a small palette: a brand blue, a darker hover shade of it, a 20% translucent tint of it for focus rings, and three grays (light, mid, dark). This run cannot write files, so put the CSS in your reply.
