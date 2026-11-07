---
description: "Legacy hold-my-hand 3 (prompt verbatim plus one line naming the steps file). MIGRATION.md has two config edits the assistant can make (config/database.yaml host, port, sslmode) and two admin-console steps only the user can do. Graders: skill-fired (with-only), edits-config and config-migrated (exp 1), presents-only-residue (llm, exp 2), performer-labeled (llm quoting exp 3). Needs --scaffold --allow-tools Edit Write."
tags: [discipline, hold-my-hand, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Edits config/database.yaml itself (db-new.internal, 6432, sslmode require), then presents only the admin-console steps, each labeled with who performs it."
---

hold my hand through this migration. Some of it needs my admin console, but do whatever you can yourself. (The steps are in MIGRATION.md.)
