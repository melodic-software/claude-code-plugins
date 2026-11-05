---
description: 'Legacy narrated-video-follows-the-audio, its first two expectations. SKILL.md lines 47-52: with /speech:narrate in the skill list, write narration/script.txt with one paragraph per beat and a blank line between, then run the skill before rendering. What /speech:narrate returns is not graded: local synthesis needs model files a run may lack, and the skill then renders silent (lines 53-54). So the case stops at the calls. Moved to pr-recorded-narration-cues-every-beat: the scene cues, --narration, no add_sound. Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Loads the speech plugin (plugins key), so /speech:narrate is in the skill list: run it against the plugins directory with --eval-dir explainer-video/evals. The SessionStart hooks of both plugins run. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, narration, no-network]
plugins: ["../..", "../../../speech"]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Writes video/narration/script.txt with a blank line between beats, calls /speech:narrate, then attempts render.py.'
---

Make a narrated explainer video of how binary search halves the range. Use ./video as the work directory. Stop after your first render attempt and tell me what happened.
