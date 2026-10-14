---
description: "Two deployables (OrdersApi, OrdersWorker) over one shared library and no container named: the component view lists both as choices and stops; it never picks one with --container and never hand-writes components.md"
tags: [architecture, map-components, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply names OrdersApi and OrdersWorker as the deployables to choose between and stops or asks for a choice. No Bash command passes --container, and no Write or Edit call targets components.md."
---

/architecture:map-components --out docs/architecture
