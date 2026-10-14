---
description: "A tiny looping scene with a supplied WAV puts the WAV marker in the template, exposes window.__pixelScene with seek, and inlines it with embed.py"
tags: [pixel-art, scene, outcome, audio]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The HTML template carries /*WAV:<relative path>*/null, assigns window.__pixelScene with a seek function, and embed.py inlines the template into one file under out/star/."
---

/pixel-art:scene A 64x36 night sky with one blinking star, a 2-second seamless loop, palette preset `pico-8`, no characters. Audio: `chime.wav` in this folder, played with the loop. Done criteria: the star blinks once per loop; the loop seam is invisible; every color is a pico-8 color. Put everything in `out/star/`, with the final file `out/star/star.html`.
