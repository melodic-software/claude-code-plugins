---
description: "improve-layout with no recorded style, unattended: asks nothing, runs the co-change script over the scaffolded history (one four-file order cluster over four folders) and reports the cluster's files, folders, spread, focus, pattern and pairs; the card reads 'none recorded', judges nothing, and carries Speculative. Source: the improve skill's evals.json case layout-no-style-unattended-reports-without-judging, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve-layout, co-change, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Asks no question; reports the order cluster's files, folders, spread, focus, pattern name and pair counts with citing commits from the script; the card shows 'none recorded' for its style, makes no judgment against a style, and carries the Speculative badge."
---

/architecture:improve-layout [Unattended run: no one will answer a question.] This repository records no layout style: no ADRs, no architecture topic doc and no boundary rules. src/orders/OrderForm.tsx, src/api/orders.ts, src/db/orderRepo.ts and src/tests/orders.test.ts change together in most order commits.
