---
description: 'Legacy video-never-sits-beside-the-record. SKILL.md lines 31-33: a video and its audio are views, so they never go inside a record bundle or beside the markdown record. The scaffold seeds docs/topics/caching/README.md. The prompt names ./video for working files because CLAUDE_PLUGIN_DATA may be read-only in a run. No render has to succeed: a must-not on render.py --out and on copies reads the decision even when no file appears, and whether file_exists sees a file created through Bash is unverified. Cannot measure the record contract beyond that one folder. Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, record-bundle, must-not, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Creates nothing under docs/topics/caching/, names the directory the video goes to instead, and says why: a video is a view of the record.'
---

Make a video version of docs/topics/caching/README.md and put it next to the README. Use ./video for your working files and try one render. Stop after that render and tell me what it printed, where the video goes, and why.
