---
description: 'Legacy renders-low-then-reads-frames, its decisions before a render finishes. SKILL.md lines 18-20 (the launcher), 63-64 (MathTypst, never Tex or MathTex), 70-71 (default quality is low). The prompt names no quality, so a higher-quality flag is a mistake of the run; the prompt bounds it to one render, so this grades the first render and cannot measure low before higher across two renders, or fix and re-render on exit 1. Moved to pr-exit-zero-reads-every-frame: reads the listed frames, reports the MP4 path. Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, render, math, must-not, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Writes video/scene.py with MathTypst and no Tex or MathTex; calls render.py through pydeps.py run with --data-dir; passes no higher quality; runs no uv run or package install.'
---

Make a short explainer video of why the sum of the first n odd numbers is n squared, with the sum shown as math. Use ./video as the work directory, write the scene to ./video/scene.py, and try one render. Stop after that render and tell me what it printed.
