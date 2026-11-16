---
description: "improve-layout unattended with a recorded style: the scaffolded cart cluster is judged against docs/adr/0004-folder-per-feature.md:9 on its card, with a proposed layout and before and after trees; the candidate artifact is written to the memory tier, then the run stops: no question, no interview, no other skill, no file moved. Source: the improve skill's evals.json case layout-unattended-stops-after-report, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve-layout, co-change, scaffold]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Cites docs/adr/0004-folder-per-feature.md:9 on the cart card with a one-sentence proposed layout and before and after folder trees, writes the layout-candidates artifact to the memory tier and names its path, then stops: asks no question, starts no interview, invokes no other skill, and moves, renames and deletes no file."
---

/architecture:improve-layout [Unattended run: no one will answer a question.] docs/adr/0004-folder-per-feature.md line 9 records "Each feature lives in one folder under src/features/." History shows src/features/cart/CartView.tsx changing with src/shared/cartTotals.ts, src/hooks/useCart.ts and src/api/cart.ts in most cart commits.
