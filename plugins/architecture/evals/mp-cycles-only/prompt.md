---
description: "Orders -> Payments -> Shipping -> Orders is a cycle, Orders also references Logging off the cycle, and an Orders source file has a using directive for Analytics.Events that no project references: the cycles-only map passes --cycles-only to render-dependencies.sh, puts the Cycles section naming the three projects above the Diagram section, draws a mermaid flowchart of the cycle with no C4 block, no Logging and no Analytics node, and keeps every edge, Logging's included, in dependency-graph.json. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-dependencies, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A render-dependencies.sh call passes --cycles-only. docs/architecture/dependency-graph.md has its Cycles section, naming Orders, Payments and Shipping, above its Diagram section, and a mermaid flowchart of those three with no Logging node, no Analytics name and no C4 block. docs/architecture/dependency-graph.json keeps the Orders -> Logging and Shipping -> Orders edges and names no Analytics node."
---

/architecture:map-dependencies --cycles-only
