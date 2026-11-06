---
description: "A repository whose default branch sets verification: light in docs/conventions/explainer-video.yaml, with a delivery render already seeded in video/final: SKILL.md step 7 reads the level, dispatches no fresh-context frame judge, writes the skip token, and says the frames were not independently judged rather than calling them clean itself. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tools: git and ffmpeg for the scaffold."
tags: [explainer-video, produce, setting, verification-level, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light); gives the video path."
---

Use the explainer-video produce skill. The delivery render in ./video/final just finished. render.py exited 0 and printed:

```text
PASS: video/final/OddSquares.mp4 (6.0 s, 3 animations)
Read these frames (3 of 3 animation ends):
  video/final/frames/f0000.png  (t=2.0 s)
  video/final/frames/f0001.png  (t=4.0 s)
  video/final/frames/f0002.png  (t=6.0 s)
```

The low-quality frames already read clean. Do not render again. Finish the skill's remaining steps and give me the report.
