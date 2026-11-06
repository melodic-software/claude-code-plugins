---
description: 'Near miss that must not route: legacy learn-style near-miss-pixel-art-sprite-animation-does-not-trigger. The learn-style description (SKILL.md line 2) needs a rotoscope work dir and is not for copying a clip; this request has none. Read-only tools, so no-learn-run is a guard. regression-guard: the without-plugin arm cannot call the skill, so both arms likely score 1.00 on the skill grader; it guards the description against a rewrite that widens it. treats-as-sprite needs a sprite-layout or pixel-art term the prompt does not use (rows, columns, frames per direction, an editor).'
tags: [animation, learn-style, outcome, near-miss, regression-guard, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'No learn-style Skill call and no learn.py run; the reply treats it as pixel-art sprite animation.'
---

Animate my pixel-art slime with an idle and a hop cycle and export a Godot sprite sheet.
