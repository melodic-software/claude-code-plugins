---
description: 'Legacy learn-style learn-a-style-pack-from-a-rotoscope-work-dir, first half: from a fresh start the skill measures the controls before it learns. learn-style SKILL.md lines 45-48 (step 1, controls.py measure with --near, --other, --source and --replica) come before line 49 (step 2, learn.py). Natural-language prompt, so learn-style-fired is a with-only indicator. ran-controls-measure needs that call with all four inputs; no-learn-before-measure fails a Bash learn.py run with no controls.py measure call before it in the trace (anchored on the Bash tool_use input, since the skill body names both). The placeholder clips and an eval run without the Python packages stop measure, so learn.py, check and selftest are graded in ls-learn-cuts-and-negatives instead. Paths refit from ~/roto and ~/clips to the workspace. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, learn-style, outcome, process, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill runs controls.py measure with --near, --other, --source and --replica before any learn.py run.'
---

Learn the style of the clip I rotoscoped in work/ into a style pack at packs/ink-short. The source clip is clips/ink-short.mp4, a filtered near miss of it is clips/near-miss.mp4, and clips/ligne-claire.mp4 is a film in another style. Shots start at 0, 4.2 and 9.8 s. Credit: Ink Short, Jo Park, https://example.org/ink-short, 2024.
