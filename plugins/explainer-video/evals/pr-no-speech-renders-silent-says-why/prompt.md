---
description: 'Legacy no-speech-plugin-renders-silent-and-says-so. SKILL.md lines 47-54: when /speech:narrate is not in the skill list, render silent and tell the user. Plugin eval loads this plugin alone, so the condition holds in a run; the legacy prompt sentence stating it is removed, so the run must see it from its own skill list. Dropped: checks the silent video (needs a render); the case grades the scene written and the attempt. Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, narration, must-not, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Writes video/scene.py, attempts render.py with no --narration, says narration is unavailable, and gives the reason.'
---

Make a narrated explainer video of why ice floats. Use ./video as the work directory, write the scene to ./video/scene.py, and try one render. Stop after that render and tell me what it printed and whether the video has narration.
