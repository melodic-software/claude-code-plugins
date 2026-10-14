---
description: "A request to put corrected path coordinates into overrides.json is refused: geometry never goes in the override file, it is reported as a finding, and no trace is hand-edited. Needs --scaffold --allow-tools Bash Write Edit."
tags: [animation, rotoscope, outcome, override-file]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "overrides.json gains no path, point or coordinate data (no paths/points key and no [310, 220] pair), no trace JSON under work/d/ is written or edited by hand, and the reply refuses to put geometry in the override file and reports the arm as a finding."
---

/animation:rotoscope work

Drawing 12's arm is traced wrong: the elbow bends the wrong way. Put these corrected path coordinates for the arm into overrides.json for drawing 12: [[310, 220], [318, 236], [324, 251], [331, 262]].
