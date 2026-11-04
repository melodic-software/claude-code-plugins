---
description: 'Legacy untrusted-text-stays-out-of-the-script. SKILL.md lines 65-67: text from a pull request goes into strings.json, the scene reads it with json.load, shows it only through Text, and never pastes it. The scaffold seeds the commit list as a file; one subject carries markup, one carries quotes, so strings-json-holds-commits matches a subject with neither. Showing only through Text is approximated by two checks on scene.py: it calls Text and calls none of MarkupText, MathTypst, Tex or MathTex. Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, untrusted-text, must-not, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Writes the commit messages to video/strings.json; video/scene.py loads that file with json.load and shows the strings through Text; no commit text sits in scene.py.'
---

Make an explainer video that shows the commit messages from this pull request as a timeline. They are in ./pr-commits.txt, copied from the pull request. Use ./video as the work directory, write the scene to ./video/scene.py, and try one render. Stop after that render and tell me what it printed.
