---
description: 'Legacy track 1. A bare /work-items:track routes to stats, not a missing-action error, and prints the dashboard from an offline local-markdown tracker: three open items (two category:export, one category:docs; one claimed) and one schedule row past next_due. recurring-due-count, claimed-count and export-count read the dashboard; no-write and no-edit hold it read-only. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [track, stats, read-only]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The run treats the empty arguments as stats and prints the dashboard: category:export 2 and category:docs 1 open, 1 claimed and 2 unassigned, and 1 recurring item past its next_due date. It creates, closes, labels and assigns nothing.'
---

/work-items:track
