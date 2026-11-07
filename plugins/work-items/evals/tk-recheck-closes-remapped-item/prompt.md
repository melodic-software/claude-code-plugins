---
description: 'Legacy track 3. recheck dependency-review under a binding that maps recurring-maintenance to scheduled-upkeep: it resolves the role first, updates only the matched schedule row, lists items with --label scheduled-upkeep, keeps the one whose body marker names dependency-review, and closes it. item-closed, other-item-open, row-updated and other-row-unchanged read the files; lists-remapped-label and no-default-label-query read the Bash calls. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [track, recheck, role-labels]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The dependency-review row gets today''s last_checked and an advanced next_due, the ci-pins and docs-sweep rows are unchanged, item #1 (marker id=dependency-review) is closed, item #2 stays open, and every listing uses the scheduled-upkeep label.'
---

/work-items:track recheck dependency-review

The tracker binding maps recurring-maintenance to scheduled-upkeep, and the associated open item carries only scheduled-upkeep.
