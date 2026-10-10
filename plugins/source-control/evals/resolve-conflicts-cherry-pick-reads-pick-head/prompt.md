---
description: "Cherry-pick stop: read CHERRY_PICK_HEAD and the current-side range, never assume MERGE_HEAD, compose LATE_RATE with the 50 cap, conclude with cherry-pick --continue"
tags: [resolve-conflicts, source-control, row22, converted]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit]
expected_outcome: "billing/rules.py keeps LATE_RATE and MAX_LATE_FEE inside min(), no markers, CHERRY_PICK_HEAD was read, no MERGE_HEAD command ran, tests ran before cherry-pick --continue, and the pick commit exists"
---

A cherry-pick stopped with a conflict in billing/rules.py. Recover both intents before resolving it, then finish the cherry-pick. There is no MERGE_HEAD in this stop.
