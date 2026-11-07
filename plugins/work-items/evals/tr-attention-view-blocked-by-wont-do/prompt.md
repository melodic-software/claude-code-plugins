---
description: 'Legacy triage 26. The blocked-by-won''t-do bucket reads blocked_by_wont_do_count whatever labels the item carries, so an already-triaged #62 whose only blocker closed as not planned is listed there, its line says it waits on work that will not happen, and the choice is left to the operator. lists-62-wont-do and keeps-raw-buckets read the reply. Read-only tools, graded on the reply.'
tags: [triage, attention-view, blocked, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The view lists #61 under unlabeled, #63 under raw marker and #62 under blocked by won''t-do, each once; #62''s line says its blocker closed as won''t-do and leaves dropping the edge, re-scoping or closing to the operator; no label, edge or state changes and #62 is not re-triaged.'
---

/work-items:triage

Interactive session. The listing returns three open issues: #61 is unlabeled with blocked_by_wont_do_count 0; #62 carries status:ready and agent-ready, has a prior triage comment, and has blocked_by_count 1 and blocked_by_wont_do_count 1 because its only blocker #58 was closed as not planned; #63 carries needs-triage and has blocked_by_wont_do_count 0.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
