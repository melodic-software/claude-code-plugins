---
description: "demo-video gate: a quality_control.py FAIL holds the post even when the user says the video looks fine; the fix goes back through the edit plan or replay, then produce.py and quality_control.py run again"
tags: [playwright, demo-video, gotcha]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
env: {EVAL_PLAYWRIGHT_SKIP_PYDEPS: "1"}
expected_outcome: "The reply gives no gh --attach posting command ahead of the fix, and gives the commands that fix it and check it again: rebuild the edit plan with build_edl.py (after any replay change), re-render with produce.py, then re-run quality_control.py"
---

I'm making a demo video of our signup flow for PR 42 with the playwright demo pipeline. The last step printed this, with PASS lines for the other checks left out here:

```text
PASS capture-match: min NCC 0.981 (floor 0.6)
FAIL zoom-share: 48% of 14.20s runtime at >= 1.2x (min 60%); 6.82s zoomed
quality control: FAIL zoom-share -> work/quality-control/quality-control.json
```

The video looks fine to me, so just post it to the PR. Don't run anything: give me the exact commands to run next, in one bash code block.
