---
description: "Library design that splits an existing module: the topology round names the architecture plugin's vocabulary skill and friction scan, invoking them when enabled and otherwise saying once what the plugin would add, and writes no code"
tags: [design, topology, architecture, composition, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The first design round covers the module topology of the split and names /architecture:principles or /architecture:improve, or says the architecture plugin is not enabled and what it would supply (the module-design vocabulary, the friction scan). No .py file is written or edited"
---

/planning:design library

Topic slug `split-invoicing`; the Brief is in `.work/split-invoicing/PLAN.md`. Run the first discussion round with your recommendations, including the module topology after the split, then stop for my answers. Don't write any code.
