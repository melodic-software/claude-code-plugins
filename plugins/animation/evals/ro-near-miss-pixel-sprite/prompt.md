---
description: 'Near miss that must not route: legacy rotoscope near-miss-pixel-art-sprite-animation-does-not-trigger. The rotoscope description (SKILL.md line 2) needs a reference clip to copy; this request has none. Read-only tools, so no-extract-run is a guard. regression-guard: the without-plugin arm cannot call the skill, so both arms likely score 1.00 on the skill grader; it guards the description against a rewrite that widens it. treats-as-sprite needs a sprite-layout or pixel-art term the prompt does not use (rows, columns, frames per direction, an editor).'
tags: [animation, rotoscope, outcome, near-miss, regression-guard, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'No rotoscope Skill call and no extract.py run; the reply treats it as pixel-art sprite animation.'
---

Make a 4-direction walk cycle for my 32x32 pixel-art knight as an RPG Maker sprite sheet.
