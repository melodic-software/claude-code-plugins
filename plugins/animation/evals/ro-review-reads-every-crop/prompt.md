---
description: 'Legacy rotoscope review-reads-every-crop-at-one-to-one, second half: with review.py''s crops on disk, the skill reads every crop, not only the flagged one, and never downscales a crop or reviews a GIF (rotoscope SKILL.md lines 65-68). The scaffold writes a passing table in measure.py''s format (table-012-050.md, every SSIM and SSIM_e at or above measure.py''s 0.98), review.py''s review-012-050.md flagging d045 only, and the four 1:1 crops under work/out/full/crops. reads-crop-d012, -d040, -d045 and -d050 each need a Read of that crop; no-downscale-or-gif and no-gif-read guard the image rule. The premise that review.py has run is stated in the prompt; ro-done-needs-review grades running it. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, rotoscope, outcome, review, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill reads all four crops under work/out/full/crops, not only the flagged d045, and resizes or GIFs none of them.'
---

/animation:rotoscope work

The measure table passes and review.py has written work/out/full/review-012-050.md with its crops. Is the replica done?
