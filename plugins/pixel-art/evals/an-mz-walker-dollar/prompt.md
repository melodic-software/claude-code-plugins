---
description: "An RPG Maker MZ single-character walker starts from kit.py, renders through backends.py, and ships sheet.png copied as $<name>.png"
tags: [pixel-art, animate, outcome, rpg-maker]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "kit.py is read, copied, or run as the starting point; backends.py renders; sheet.png is copied to a $-prefixed PNG in out/mage/ and the final reply names that $-prefixed file."
---

/pixel-art:animate An RPG Maker MZ single character (one character per image, not an 8-character sheet): a small mage in a blue robe and pointed hat, chibi proportions, palette preset `pico-8`, 4-direction walk, MZ's standard 3 patterns per direction. Name it `mage`. Done criteria: the hat silhouette reads in every direction at 1x; the stride is visible in the side views. Put everything in `out/mage/`.
