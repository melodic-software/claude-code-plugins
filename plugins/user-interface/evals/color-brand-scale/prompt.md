---
schema_version: "1.1"
name: color-brand-scale
description: "Hard (the brand color is given in hex and HSL ramps are the habit): a tonal scale built from a brand hex is written in oklch with one fixed hue on every step and endpoints short of black and white"
tags: [web, color, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The scale is CSS custom properties from a 50 step to a 950 step, every step written in oklch(), every step carrying the same hue, and neither endpoint at lightness 0 or 1"
---

Build a tonal palette for our brand color #4f46e5, steps 50 through 950, as CSS custom properties named like `--brand-500`. I usually just step the lightness in HSL. This run cannot write files, so put the CSS in your reply.
