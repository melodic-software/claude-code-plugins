---
description: "The user's approval is recorded by running produce.py approve with their words as the note, never by hand-writing approval.json. Needs --scaffold --allow-tools Bash Write Edit."
tags: [animation, produce, outcome, approval-gate]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill records the approval by running produce.py approve on film with --note carrying the user's words (heavy blacks), so boards/approval.json holds that note. It never writes or edits boards/approval.json itself."
---

/animation:produce film

I reviewed the boards in film/boards. My answer: "Approved - love the heavy blacks, go ahead". Carry on with the film.
