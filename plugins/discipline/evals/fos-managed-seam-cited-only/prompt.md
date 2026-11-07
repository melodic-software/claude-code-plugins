---
description: "Legacy follow-our-standards 4 (prompt verbatim, its dash a colon, plus one line naming the edited files). standards-sync.yaml marks .github/workflows/lint.yml upstream-managed; the user's edit there sets continue-on-error, breaking ci.md CI-1. src/report.py breaks logging.md LOG-1 and also uses a one-letter name no standard covers (an uncitable opinion). Graders: skill-fired (with-only), only-cited-findings (llm, exp 1), no-managed-edit, no-managed-write and routes-upstream (llm) for exp 2, no-convention-restated (not_contains of two long sentences from the standards docs, exp 3). Bash is not granted, so no shell write path exists. Needs --scaffold --allow-tools Edit Write."
tags: [discipline, follow-our-standards, outcome, scaffold, managed-seam, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Cites logging.md and ci.md for the two real findings, drops the uncitable naming opinion, routes the lint.yml change upstream without editing it, and does not copy the convention text."
---

follow our standards: audit my edits. One of the files I changed is marked upstream-managed in our standards distribution's manifest. (My edits this session: src/report.py and .github/workflows/lint.yml.)
