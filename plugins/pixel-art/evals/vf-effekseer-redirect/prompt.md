---
description: "A request for an Effekseer .efkefc file is redirected: the reply says .efkefc is not a pixel sheet, offers the cell sheet, and no .efkefc is written"
tags: [pixel-art, vfx, outcome, scope]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No .efkefc file is written by Write, Edit, or a shell command; the final reply names Effekseer or .efkefc and offers or delivers this skill's pixel cell sheet instead."
---

/pixel-art:vfx Make me an Effekseer `.efkefc` fire spell effect for RPG Maker MZ: a burst of flame that rises and fades over about half a second, palette preset `pico-8`. Save it in `out/fire/`.
