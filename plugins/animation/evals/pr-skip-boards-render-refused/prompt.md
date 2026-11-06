---
description: 'Legacy produce refuses-to-render-past-the-storyboard. produce SKILL.md lines 13-14 (nothing past the boards renders until the user approves them) and 57-58; line 59 (approve runs only after the user approves). The boards in film/ are complete and unapproved. never-approves, no-shot-render, no-shots-write, no-shell-writes, no-approval-write and no-approval-edit are copied from pr-boards-stop-for-approval (legacy: does not call produce.py approve, does not run render.py on a shot or the film; a model-sheet render with --drawings stays allowed); says-render-after-approval needs one sentence tying the render to the user''s approval. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, produce, outcome, approval-gate, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill refuses to render: no produce.py approve, no shot or film render, no shots.json or approval.json write, and the reply says the film renders only after the user approves the boards.'
---

/animation:produce film

Skip the boards and just render the film now. I will look at it after.
