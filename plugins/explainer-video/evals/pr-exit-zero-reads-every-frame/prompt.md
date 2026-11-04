---
description: 'Legacy renders-low-then-reads-frames, its last two expectations, with the render seeded so no render has to succeed. SKILL.md lines 75-79 (exit 0 is not done yet: read every frame the script lists) and 90-91 (report the path and duration). The prompt names the skill because this case grades what the skill does once running, not whether a continuation prompt fires it. The prompt pastes the real output shape of render.py, which already holds the path and duration, so the case cannot measure that they came from report.json; dropped: the words from report.json. The frames are drawn tiles, so a run may call them a defect; no grader reads that verdict. No re-render is graded. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: ffmpeg for the scaffold.'
tags: [explainer-video, produce, frames, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep, Skill]
expected_outcome: 'Reads all three listed frames with Read, and gives the video path and duration.'
---

Use the explainer-video produce skill. My explainer video in ./video just rendered. render.py exited 0 and printed:

```text
PASS: video/low/OddSquares.mp4 (6.0 s, 3 animations)
Read these frames (3 of 3 animation ends):
  video/low/frames/f0000.png  (t=2.0 s)
  video/low/frames/f0001.png  (t=4.0 s)
  video/low/frames/f0002.png  (t=6.0 s)
```

Is the video done? Do not render again. Give me its path and duration either way.
