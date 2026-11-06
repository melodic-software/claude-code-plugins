---
description: 'Legacy setup pinned-version-mismatch-is-reported-as-a-reproducibility-caveat. Narration: the table is the user''s render box, not this machine, so this host''s probe cannot contradict it, and the case grants no Bash. Slash-invoked (setup SKILL.md line 5), no Skill grader. Lines 33-35: an INFO on numpy means a version other than the pin in requirements.in: scripts run, but statistics may differ from the shipped pack and regression. Lines 15-16 (the SessionStart hook installs the Python packages) and 27-28 (the scripts run through pydeps.py run). The pin is refit from the legacy 2.5.3 to 2.5.4 (requirements.in line 2). info-not-fail fails a reply that calls the row a FAIL; stats-may-differ needs the caveat naming the pack and the regression; points-at-pydeps-run needs pydeps.py run; no-pip-fix fails a reply that recommends pip install or uv add (a sentence- or line-initial command, fenced or after a $ prompt; a run, try, use, fix or install verb, any inflection, opening its sentence or a clause after a comma, colon or semicolon; or try, use, you can or should, recommend or suggest earlier in the sentence) and passes a sentence that only describes the hook installing with pip install --require-hashes (legacy: not a bare python or a fetch at run time).'
tags: [animation, setup, check, narration, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply keeps the numpy row INFO, says statistics may differ from the shipped pack and regression, points at pydeps.py run, and recommends no pip install or uv add.'
---

/animation:setup check

On my render box, not this machine, the table shows numpy INFO: 2.4.0, not the pinned 2.5.4.
