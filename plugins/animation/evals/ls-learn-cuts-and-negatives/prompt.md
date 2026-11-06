---
description: 'Legacy learn-style learn-a-style-pack-from-a-rotoscope-work-dir, second half: once controls.py measure has run, the skill learns the pack with the shot starts as --cuts and the calibration half as --negative (learn-style SKILL.md lines 49-52), and the pack holds statistics only (lines 14-15). The scaffold writes the work dir and measure''s out/calibration and out/evaluation summaries. ran-learn-cuts-negative needs one learn.py call with --cuts 0,4.2,9.8 and --negative out/calibration/...; selftest-names-pack fails a controls.py selftest with no pack argument (line 55). no-other-pack-file, no-geometry-write, no-geometry-edit, no-shell-copy and style-json-no-paths keep traced geometry, source frames and the clip out of packs/ink-short (legacy: does NOT copy them into the pack). Held: check''s every-control-fails rule and a selftest that runs, since an eval run without the Python packages stops learn.py first. Paths refit from ~/roto to the workspace. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, learn-style, outcome, process, pack-integrity, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'One learn.py call carries --cuts 0,4.2,9.8 and --negative out/calibration/...; no selftest call lacks the pack; nothing but style.json and STYLE.md is written into packs/ink-short, and no traces, frames or clip are copied there.'
---

controls.py measure already ran: its summaries are in out/calibration and out/evaluation. Now learn the style of the clip I rotoscoped in work/ into a style pack at packs/ink-short. Shots start at 0, 4.2 and 9.8 s. Credit: Ink Short, Jo Park, https://example.org/ink-short, 2024.
