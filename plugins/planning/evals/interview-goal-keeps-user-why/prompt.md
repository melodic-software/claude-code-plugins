---
description: "Unattended lock whose request states the user's reason and where the work heads, and no tiebreak between goals: the Brief's Goal carries the Intent line in the user's own words, the Vision line, and 'When goals conflict, prefer: none stated'"
tags: [interview, brief, goal, intent, vision]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: ".work/intake-import/PLAN.md has, under ### Goal, a '- Intent (why, in the user's words):' line quoting 're-keying the weekend's paper forms', a '- Vision (where this heads):' line about every intake channel landing in one queue, and '- When goals conflict, prefer: none stated'"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going.

Lock the Brief. Use the topic slug `intake-import`.

Goal: support staff can upload a scanned intake form and get a draft ticket with its fields filled in. This is an internal tool. Nothing says another form type is coming, so keep it specific to the intake form.

Why I want this: our support team loses every Monday morning re-keying the weekend's paper forms.

Where this heads: eventually every intake channel, paper, email and phone notes, lands in one queue.

Acceptance: an uploaded scan of the intake form produces a draft ticket whose name, phone and issue fields match the form; a scan with an unreadable field leaves that field empty and flags the ticket for review.
