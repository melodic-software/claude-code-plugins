---
description: "Legacy mind-your-maxims 1 (prompt verbatim, its dash a colon). The chained history holds the migration answer: padded (praise, Postgres history, a restatement, a summary) and missing necessary steps (stop the old cluster, a pg_upgrade --check dry run, a backup, analyze afterwards). Graders: skill-fired (with-only), quantity-named, flags-omission (llm, exp 1), flags-padding (llm, exp 2), located-and-corrected (llm, exp 3). A history_file case runs single-arm on a path target."
tags: [discipline, mind-your-maxims, outcome, history, no-network]
max_turns: 10
timeout_seconds: 400
allowed_tools: [Skill, Read]
expected_outcome: "Names the missing steps as under-informing and the padding as over-informing, each located, and gives the corrected answer."
---

mind your maxims: review the answer I just gave the user about the migration steps.
