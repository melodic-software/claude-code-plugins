---
description: "demo-video main path: a request for a PR demo video gets the skill's pipeline in order (record.mjs, build_edl.py, produce.py, quality_control.py), with quality control run through the pydeps.py launcher, not a bare python3"
tags: [playwright, demo-video]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
env: {EVAL_PLAYWRIGHT_SKIP_PYDEPS: "1"}
expected_outcome: "The reply lays out the demo-video pipeline in order: replay with record.mjs, build the edit plan with build_edl.py, render with produce.py, then check the frames with quality_control.py, each Python script run through pydeps.py run"
---

I want a produced demo video of the new signup flow at http://localhost:3000 to attach to PR 42. Don't run anything yet: give me the exact commands you would run to record, render and check the video, in order, in one bash code block.
