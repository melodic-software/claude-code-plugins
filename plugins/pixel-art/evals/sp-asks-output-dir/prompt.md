---
description: "A fully specified sprite request with no output location anywhere asks where to put the files before any render"
tags: [pixel-art, sprite, outcome, output-dir]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No output path is in the request, the project, or the output_dir option, so the skill asks where to write the files and runs neither backends.py nor render.py before the answer."
---

/pixel-art:sprite A 16x16 wooden treasure chest icon with a gold lock, front view, palette preset `nes`, plain PNG target, neutral mood, no style reference. Done criteria: the lock is the brightest cluster; the lid seam reads at 1x.
