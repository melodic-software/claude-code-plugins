---
description: 'Legacy scan-todos 3, and the classify half of legacy scan-todos 1. With --work the skill presents the groups, picks the smallest (lib/, one marker) without asking, classifies its marker as significant work, files it through /work-items:track add, and removes the inline marker; src/ is left for a later pass. smallest-group-cleared and other-groups-untouched read the files, files-via-track the Skill call, item-filed the new item file, no-gh-create forbids a raw gh issue create, no-group-question forbids asking which group. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [scan-todos, work-flag, filing]
max_turns: 30
timeout_seconds: 720
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit, Skill]
expected_outcome: 'The run presents lib/ (1) before src/ (2), selects lib/ on its own, files the job-queue marker as a work item through /work-items:track add, removes the TODO line from lib/stream.py, leaves src/report.py''s markers in place, and reports a results table.'
---

/work-items:scan-todos --work
