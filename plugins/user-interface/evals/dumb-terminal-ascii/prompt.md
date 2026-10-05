---
schema_version: "1.1"
name: dumb-terminal-ascii
description: "TERM=dumb and missing Nerd Font fall back to plain ASCII markers and no color"
tags: [terminal]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The design replaces glyphs and Nerd Font icons with plain ASCII markers such as [ok] and [FAIL], drops color under TERM=dumb, and puts the icon set behind an option or detection"
---

Our test runner prints ✔ and ✖ plus a Nerd Font icon per suite, all in color. Some users run it in Emacs
shell mode with `TERM=dumb`; others have no Nerd Font installed. Design what it prints for each group,
in under 150 words.
