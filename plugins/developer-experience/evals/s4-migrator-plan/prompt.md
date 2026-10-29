---
description: "Scenario S4 (data-migration helper), plan turn: build-cli shows its plan and changes no file before the user says yes (item 8), and withholds the backup format the user left open, asking it as a question (item 10). The items graded on the built helper need the second turn, which this case does not send"
tags: [build-cli, s4, plan-turn]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "build-cli fires and replies with a plan for the migration helper with no Write or Edit call and no shell command that writes a file; the plan asks whether the backup is a plain copy or a gzip archive and recommends neither"
---

Write a helper that migrates data/accounts.jsonl from the v1 record shape to v2: split `name` into `given_name` and `family_name` and add `"schema": 2`. Keep a backup of the v1 file first, as a plain copy or as a gzip archive. We'll run it on staging and on laptops.
