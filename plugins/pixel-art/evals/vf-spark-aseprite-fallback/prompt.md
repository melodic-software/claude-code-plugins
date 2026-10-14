---
description: "A spark requested through the aseprite backend, with Aseprite absent, runs backends.py with aseprite, falls back to native with a notice, and delivers sheet.png and a GIF"
tags: [pixel-art, vfx, outcome, backend]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "backends.py runs with the aseprite backend named; with Aseprite absent it falls back to native and the final reply says so; the reply names sheet.png and a .gif."
---

/pixel-art:vfx A 4-frame 16x16 hit spark as a plain strip (no engine), palette preset `pico-8` stepping white, yellow, orange, red, not looping. Render it with the aseprite backend. Done criteria: frame 2 is the largest burst; the last frame uses only the darkest ramp step. Put everything in `out/spark/`.
