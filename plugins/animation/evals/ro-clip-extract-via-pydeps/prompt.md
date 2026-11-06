---
description: 'Legacy rotoscope rotoscope-a-clip-runs-the-extract-measure-fit-review-loop, first step. rotoscope SKILL.md lines 18-21 (every script through pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" --), 25 (work dir outside the plugin), 55 (extract.py <work> --video <clip> first), 57-61 (--playwright-core on measure.py and fit.py), 13-14 (never replay or embed source bitmaps). Natural-language prompt, so rotoscope-fired is a with-only indicator. ran-extract-via-pydeps needs that extract call through pydeps.py run with --data-dir; scripts-through-pydeps fails a bare python run of a rotoscope script; measure-fit-get-playwright-core fails a measure.py or fit.py call without --playwright-core; work-dir-outside-plugin, no-bitmap-write and no-bitmap-edit guard the other two rules. Held: measure, fit and review as positives and the measure-table report, since the clip is a one-second plain clip and an eval run may lack the Python packages. Paths refit from ~/clips and ~/roto to the workspace. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, rotoscope, outcome, process, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill runs extract.py roto/ink-short --video clips/ink-short.mp4 through pydeps.py run --data-dir, runs no rotoscope script by bare python, passes --playwright-core to any measure.py or fit.py call, keeps the work dir out of the plugin, and writes no source bitmap into the replica.'
---

Rotoscope this clip one to one: clips/ink-short.mp4. Use roto/ink-short as the work dir.
