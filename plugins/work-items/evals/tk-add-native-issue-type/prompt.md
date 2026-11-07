---
description: 'Legacy track 6. add with --type fix in an organization repository maps the type to Bug and passes it to the seam''s --type as the native Issue Type, adding no type: label, no class label and no status field. native-bug-type reads the reply. Read-only tools, graded on the reply.'
tags: [track, add, issue-type, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The item is created through the seam with --type Bug (the native Issue Type), and its labels carry no type: label and no class label; no status field is written.'
---

/work-items:track add "Export fails on empty ledger" --type fix

The repository is in an organization, so native Issue Types are available.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does and why.
