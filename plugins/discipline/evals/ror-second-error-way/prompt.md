---
description: "Two modules return Result values; a new invoices module throws a custom error instead, a silent second way. The run must name the second way and correct the new module to reuse Result, leaving the established modules alone"
tags: [discipline, reuse-or-replace, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Names the second (parallel) error-handling way, edits src/invoices.ts to import from ./lib/result and stop throwing InvoiceError, and makes no Edit or Write to users.ts, orders.ts or result.ts."
---

/discipline:reuse-or-replace src/invoices.ts, which I just added
