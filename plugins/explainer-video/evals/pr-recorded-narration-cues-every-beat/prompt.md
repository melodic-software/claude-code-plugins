---
description: 'Legacy narrated-video-follows-the-audio, its scene and render expectations. SKILL.md lines 47-48 (narration is available when /speech:narrate is in the skill list), 57-60 (from narration import beat, a cue for each beat), 70-71 (--narration) and 148-149 (no add_sound). The scaffold seeds a consistent narration folder of three paragraphs, so beats run 0 to 3 (scripts/narration.py beat_defects) and no synthesis is needed. scene-cues-beats-in-order reads literal calls, so a loop over beats fails it. Moved to pr-narrated-writes-script-calls-narrate: writes the script, runs /speech:narrate. Dropped: reports the MP4 as narrated (needs a render). Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Loads the speech plugin (plugins key), so /speech:narrate is in the skill list: run it against the plugins directory with --eval-dir explainer-video/evals. The SessionStart hooks of both plugins run. Host tools: python3 for the scaffold, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, narration, must-not, no-network]
plugins: ["../..", "../../../speech"]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'video/scene.py imports beat from narration, cues beats 0 to 3 in order and has no add_sound; render.py is attempted with --narration on the narration folder.'
---

Make a narrated explainer video of how binary search halves the range. The narration is already recorded and final in ./video/narration (script.txt, narration.wav and words.json, one paragraph per beat), so do not narrate it again. Use ./video as the work directory, write the scene to ./video/scene.py, and try one render. Stop after that render and tell me what it printed.
