---
description: "A tone-level change for a drawing range goes into overrides.json as a levels entry and is applied with extract.py --apply, never by editing the trace JSON"
tags: [animation, rotoscope, outcome, override-file]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "overrides.json gains an entry with k [40, 50] and levels [40, 80, 170, 215]; the skill runs extract.py on work with --apply (it may stop on a missing package); no trace JSON under work/d/ is written or edited by hand."
---

/animation:rotoscope work

The tone layers on drawings 40 to 50 look muddy. Set their tone levels to 40, 80, 170 and 215 and retrace them.
