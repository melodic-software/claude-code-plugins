---
description: 'Legacy track 4. audit under a binding that maps recurring-maintenance to scheduled-upkeep resolves the role at entry, reconciles orphans with --label scheduled-upkeep, never queries the recurring literal, and so flags neither due row as orphaned. lists-remapped-label and no-default-label-query read the Bash calls, no-false-orphan the reply, no-write and no-edit keep the audit a read. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [track, audit, role-labels]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The audit lists recurring items with --label scheduled-upkeep, never --label recurring, finds the open items #1 and #2 for the two due rows, and reports no false orphan finding.'
---

/work-items:track audit

The tracker binding maps recurring-maintenance to scheduled-upkeep. Existing maintenance items use that label exclusively.
