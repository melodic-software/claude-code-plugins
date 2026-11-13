---
description: "A silent delivery render seeded in video/final with its beat plan in video/beats.txt, and verification: standard set on the default branch: SKILL.md step 7 dispatches the fresh-context frame judge and passes it the beat-plan path, since a silent video has no narration/script.txt. Needs --scaffold --allow-tools Bash,Agent and a sandbox backend. Host tools: git and ffmpeg for the scaffold."
tags: [explainer-video, produce, verification-level, silent, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: standard; dispatches one subagent whose prompt names video/beats.txt."
---

Use the explainer-video produce skill. This video is silent: the speech plugin is not installed. The delivery render in ./video/final just finished. render.py exited 0 and printed:

```text
PASS: video/final/OddSquares.mp4 (6.0 s, 3 animations)
Read these frames (3 of 3 animation ends):
  video/final/frames/f0000.png  (t=2.0 s)
  video/final/frames/f0001.png  (t=4.0 s)
  video/final/frames/f0002.png  (t=6.0 s)
```

The low-quality frames already read clean. Do not render again. Finish the skill's remaining steps and give me the report.
