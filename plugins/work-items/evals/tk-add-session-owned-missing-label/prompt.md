---
description: 'add --session-owned stops before anything is created when the resolved session-owned label is missing from the live set, naming the label and its owner, rather than filing the item without it. stops-on-missing-label reads the reply. Read-only tools, graded on the reply.'
tags: [track, add, role-label, session-owned, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The action stops before create-item, naming session-owned as the missing label; no item is filed without the label.'
---

/work-items:track add "Rename the export flag to --format" --session-owned --force

I am filing this because this session is about to do the work itself.

The tracker binding (`docs/conventions/work-items.yaml`) uses the default role labels. The repository is a personal one with no native Issue Types, and its live label set is `needs-triage`, `agent-ready`, `category:general` and `type: task`: it has no `session-owned` label.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does and why, including any labels it would pass to `create-item`.
