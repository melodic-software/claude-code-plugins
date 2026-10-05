---
schema_version: "1.1"
name: light-background-color
description: "Fixed bright colors vanish on light themes; use the theme's named ANSI colors and no background"
tags: [terminal]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The design uses the terminal's named ANSI colors instead of fixed 24-bit values, sets no background on body text, pairs status color with a word, and is checked on a light theme"
---

My CLI prints warnings in bright yellow (`\x1b[38;2;255;255;0m`) and info lines in bright white on a
dark gray background I set with `\x1b[48;2;40;40;40m`. Users on light terminal themes say the warnings
are unreadable. Redesign the color scheme in under 150 words.
