---
description: "A digits-only Godot bitmap font renders a glyph grid and writes a text BMFont .fnt beside sheet.png with sheet.png as the page and one char entry per digit"
tags: [pixel-art, ui, outcome, font]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "backends.py renders the glyph sheet; out/digits/digits.fnt is created, its page line names sheet.png, and it holds a char entry for every id from 48 to 57."
---

/pixel-art:ui A bitmap font of the digits 0-9 only, for Godot as a text BMFont, 4x6 glyphs in 5x8 cells, one row in order 0 to 9, palette preset `pico-8` (white glyphs). Done criteria: no glyph touches its cell edge; 1 and 7 are distinct at 1x. Put everything in `out/digits/`, with the font file `out/digits/digits.fnt`.
