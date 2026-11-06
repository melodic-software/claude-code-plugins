---
description: "Narration: the user reports an empty fleet run on a machine without ghq (the eval sandbox has no ghq either, so the pre-computed ghq row agrees). setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 59-62: ghq is optional; absent is INFO, not a defect; the batch actions still take --repo (repeatable, glob-expanded) and --repos-from FILE|-; only the ghq-derived enumeration is unavailable, so report it rather than letting an empty list look like a bug. Line 48: run no mutating tier. ghq-info and ghq-not-fail grade the status; names-repo-inputs, only-ghq-unavailable and empty-list-expected grade the explanation; no-batch-run fails any batch script run (dry-run included, a --help read allowed) and no-clean-skill fails invoking clean to reproduce the empty list. Bash is in allowed_tools for the pre-computed line and so no-batch-run can fail. Needs --allow-tools Bash."
tags: [repo-hygiene, setup, outcome, check, narration, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply reports ghq as INFO, not FAIL, names --repo and --repos-from as the inputs the batch actions still take, and says only the ghq enumeration is missing, so the empty list is expected; no batch action runs."
---

/repo-hygiene:setup check A fleet batch action found no repositories on this machine, and I do not have ghq installed. Is the batch action broken?
