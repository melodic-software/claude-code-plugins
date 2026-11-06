---
description: "The user's approval is recorded by running produce.py approve with their words as the note, never by hand-writing approval.json; then shots.json is the cut list (legacy produce shots-json-is-the-cut-list). produce SKILL.md line 38 and produce.py lines 274-277: the first t0 is 0 and each t1 meets the next t0; lines 71-72 and 88: inkstats.py --cuts takes the shots.json path, never a retyped list. shots-first-t0-zero and shots-t1-meets-t0 read film/shots.json; inkstats-cuts-shots-json fails an inkstats.py --cuts that is not a shots.json path. Held: reading frames at 1:1 before calling the film done, since that needs a full render and the fresh-context review past this case's turn budget. Needs --scaffold --allow-tools Bash Write Edit."
tags: [animation, produce, outcome, approval-gate, no-network]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill records the approval by running produce.py approve on film with --note carrying the user's words (heavy blacks), so boards/approval.json holds that note. It never writes or edits boards/approval.json itself. Its film/shots.json starts at t0 0 with each t1 meeting the next t0, and no inkstats.py --cuts call gets anything but the shots.json path."
---

/animation:produce film

I reviewed the boards in film/boards. My answer: "Approved - love the heavy blacks, go ahead". Carry on with the film.
