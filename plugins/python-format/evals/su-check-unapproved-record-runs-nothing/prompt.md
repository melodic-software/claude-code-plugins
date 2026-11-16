---
description: "check on a branch that committed a python record absent from the default branch, with a ruff.toml present. setup SKILL.md check step 3: approval unapproved is FAIL; the hooks run nothing for that concern, not even the adapter; remediation is merging or apply approve-record. The check never approves: an approve command would be an unasked write. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network, record, approval]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Write, Edit or approval. The reply says the record is unapproved, so nothing runs for those concerns (Ruff does not take over), and names merging or apply approve-record."
---

/python-format:setup check

I added a python record on this branch. Why didn't my last edit get formatted?
