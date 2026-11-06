---
description: 'Legacy rotoscope hand-decisions-go-in-the-override-file. rotoscope SKILL.md lines 37-51 (every hand decision is an overrides.json entry; brush bias), 60-62 (fit.py --only bisects bias and appends to overrides.json), 57 (measure.py --only K0-K1), 69-70 (append to learnings.md). bias-entry-or-fit reads the trace for a Write, Edit or Bash change to overrides.json adding a k [40, 55] entry with a bias, or a fit.py run with --only 40-55 (legacy allows either); no-trace-write, no-trace-edit and no-shell-trace-write are copied from ro-levels-override-apply (not by editing traced paths); remeasures-range needs measure.py --only 40-55 and no-full-remeasure fails a measure.py run without --only; learnings-name-change needs a learnings.md line naming the range and the change. Held: the before and after numbers, since the fixture has no source drawings, so measure.py cannot produce any. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, rotoscope, outcome, override-file, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'overrides.json gains a k [40, 55] bias entry (or fit.py runs with --only 40-55); no trace JSON is edited; measure.py runs with --only 40-55 and never over the whole clip; learnings.md gains a line naming the range and the change.'
---

/animation:rotoscope work

Drawings 40 to 55 of my rotoscope replica are too thin. Fix just those.
