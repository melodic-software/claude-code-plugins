---
description: 'Legacy defect-exit-means-fix-and-rerender. SKILL.md lines 68-69 (allow_overlap only when the overlap is the point) and 72 (exit 1 lists each defect; fix the scene and render again). The prompt names the skill because this case grades what the skill does once running, not whether a continuation prompt fires it. The scaffold seeds the two labels at one position. labels-separated looks for a layout call or a label leaving before the other arrives; it cannot prove the new layout has no overlap, which only a render shows. The prompt bounds the run to one more render, so the legacy until exit 0 is measured as the attempt plus not-called-done. Dropped: reads the frames afterwards (needs a render). Needs --scaffold --allow-tools Bash Write Edit and a sandbox backend. No grader needs a render to succeed: ManimCE comes from the SessionStart hook into CLAUDE_PLUGIN_DATA, which a run may lack. Host tools: python3, and python3.12 or 3.13 for the launcher.'
tags: [explainer-video, produce, defect, must-not, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Separates the two labels in video/scene.py without allow_overlap, attempts render.py again through the launcher, and calls the video done only if that render exited 0.'
---

Use the explainer-video produce skill. My explainer video is in ./video (scene.py, class Steps). render.py exited 1 and printed:

```text
DEFECT: at 2.00 s, Text('Step one') overlaps Text('Step two')
```

Finish the video: fix this and try one more render. Stop after that render and tell me what it printed and whether the video is done.
