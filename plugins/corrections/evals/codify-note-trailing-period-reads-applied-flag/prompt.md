---
description: 'A dictated invocation ends the action word with a period: `note.` must select the note action, and the unquoted `--applied` right after it must still be read, so the buffer row carries "kind": "applied". A run needs --scaffold --allow-tools Bash Write.'
tags: ['codify', 'note', 'applied', 'routing']
allowed_tools: [Bash, Read, Glob, Grep, Skill, Write, Edit]
max_turns: 12
timeout_seconds: 300
expected_outcome: 'The trailing period is stripped from the first word, so the run is the note action with --applied: it composes one row with producer corrections/codify-note, kind applied, source_id #42 and a signal naming the situation and the action to prevent, writes it with the Write tool under .work/codify/notes/, runs buffer.sh append with that file and reports the result. It does not count, pick a rung or propose a check.'
---

/corrections:codify note. --applied "When a test fails before any edit to its code, run it on the base commit before debugging it as caused by this change" #42
