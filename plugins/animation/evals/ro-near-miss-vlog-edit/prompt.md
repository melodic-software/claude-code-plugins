---
description: 'Near miss that must not route: legacy rotoscope near-miss-generic-video-editing-does-not-trigger. The rotoscope description (SKILL.md line 2) needs a reference clip to copy; this request has none. Read-only tools, so no-extract-run is a guard. regression-guard: the without-plugin arm cannot call the skill, so both arms likely score 1.00 on the skill grader; it guards the description against a rewrite that widens it.'
tags: [animation, rotoscope, outcome, near-miss, regression-guard, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'No rotoscope Skill call and no extract.py run.'
---

Trim the first 3 seconds off my vlog, add a crossfade between the two scenes and export it at 1080p.
