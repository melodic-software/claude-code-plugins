---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Lists the recorded OrderStore entry as already recorded and does not propose it again. Reports the two other writers as a divergence from it, citing both lines and the entry''s source, and on the yes invokes /corrections:codify through the Skill tool with a description naming the convention and the departing places. It writes no check, no rule and no paved-path entry itself.'
---

/architecture:improve conventions. docs/standards/paved-paths.md, the file the standards index's paved-path row points at, records that OrderStore in src/Orders/OrderStore.cs is the one writer of order.status. src/Shipping/ShipmentJob.cs:42 and src/Billing/RefundService.cs:77 also assign order.status. /corrections:codify is available. When you propose handing this on, I say yes.
