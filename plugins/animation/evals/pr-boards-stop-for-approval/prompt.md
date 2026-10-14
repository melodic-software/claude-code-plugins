---
description: "Boards that pass the gate stop the skill: it asks the user to approve them and does not record approval, write shots.json, or render a shot"
tags: [animation, produce, outcome, approval-gate]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill runs produce.py boards on film (it exits 0), then stops and asks the user to approve the boards. It never runs produce.py approve, never writes or edits boards/approval.json or shots.json, and runs no shot render (render.py without --drawings)."
---

/animation:produce film

The boards are done: brief, style guide, palette, vibe, the keeper sheet and a three-panel storyboard are all in film/. Carry on and make the film.
