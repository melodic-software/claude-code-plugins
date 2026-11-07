---
description: 'Legacy track 2. The binding maps recurring-maintenance to scheduled-upkeep, so due resolves the role at action entry, lists open items with --label scheduled-upkeep, matches each due row to its item by the body''s recurring-schedule marker, and reports neither due row as orphaned. lists-remapped-label and no-default-label-query read the Bash calls, no-false-orphan and matches-both-items the reply. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [track, due, role-labels]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The due table lists dependency-review with #1 and ci-pins with #2, both matched by their recurring-schedule markers; every listing uses --label scheduled-upkeep, none uses --label recurring, and no due row is reported orphaned.'
---

/work-items:track due

The tracker binding maps recurring-maintenance to scheduled-upkeep. There are open scheduled-upkeep items, but no label named recurring.
