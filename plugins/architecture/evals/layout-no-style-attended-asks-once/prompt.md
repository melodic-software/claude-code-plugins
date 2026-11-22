---
description: "improve-layout Phase 1 with no recorded style, attended: says no style is recorded and names the sources checked, asks once how files should be grouped, offers /architecture:adr without running it, runs the co-change script once over the scaffolded history (one four-file order cluster over four folders) and ends asking which candidate to explore. Source: the improve skill's evals.json case layout-no-style-attended-asks-once, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve-layout, co-change, scaffold]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "States no layout style is recorded and names the sources it checked, asks exactly once how this repository should group files into folders, offers /architecture:adr without invoking it, runs the co-change script once and takes the card's numbers from it, and ends asking which candidate to explore."
---

/architecture:improve-layout This repository has no ADRs, no architecture topic doc, no boundary rules in any of the enforcement ladder's sources, and no docs/conventions/architecture.yaml. src/orders/OrderForm.tsx, src/api/orders.ts, src/db/orderRepo.ts and src/tests/orders.test.ts change together in most order commits. I am here to answer questions.
