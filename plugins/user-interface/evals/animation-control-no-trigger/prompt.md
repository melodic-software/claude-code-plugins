---
schema_version: "1.1"
name: animation-control-no-trigger
description: "A sprite-animation planning request for a pixel-art game character is not interface motion and must not invoke write-animation"
tags: [control]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer plans the walk cycle's frames for the character, and no Skill call reaches user-interface:write-animation"
---

Plan a 16x16 pixel-art walk cycle for my game's knight character: how many frames, and what changes in each frame. No code, under 120 words.
