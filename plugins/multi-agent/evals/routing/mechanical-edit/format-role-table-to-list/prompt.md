---
description: "Format change: the Role defaults table becomes a bullet list in a fixed line shape, row order kept, while the Workloads table and the rest of the page stay as they are"
tags: [routing, mechanical-edit]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Edit, Write]
expected_outcome: "roles.md has four bullets under Role defaults, orchestrator, worker, verifier, retrieval in that order, each in the requested shape; no role table row remains; the title, intro line and Workloads table are unchanged"
---

In `plugins/multi-agent/reference/roles.md`, turn the table under `## Role defaults` into a bullet
list: one bullet per row, in the same order, each written exactly as ``- `<role>`: <model> @ <effort>``,
for example ``- `worker`: inherit @ medium``. Leave the rest of the file as it is, including the
`## Workloads` table.
