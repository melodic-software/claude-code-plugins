---
description: "An invalid repository code_writing value is named with its file, key and value and resolves the default inline, while a valid repository integration_posture is reported with the repository file as its layer."
tags: [implement, concise-rollout, setting, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The model reads docs/conventions/implementation.yaml, names its code_writing value parallel as invalid with the file and key, reports code_writing: inline (default), and reports integration_posture: minimal (docs/conventions/implementation.yaml). It edits nothing."
---

/implementation:implement fix `late_fee` in `ledger/fees.py` charges 3 per overdue day; it should charge 2. The working directory is the root of a git repository (not your home directory), on branch `fix/late-fee` with a clean tree. This run is a settings check only: do not edit any file, do not run commands and do not dispatch agents. Resolve every setting the skill resolves before its first edit, print one line per setting with the layer that supplied it, and stop.
