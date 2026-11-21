---
description: 'add --session-owned with --agent-ready stops before any read or write, naming both flags, because the two make opposite ownership claims. no-create-item reads the reply. Read-only tools, graded on the reply.'
tags: [track, add, role-label, session-owned, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The action stops before the duplicate check and creates nothing, naming --session-owned and --agent-ready as the conflicting pair.'
---

/work-items:track add "Rename the export flag to --format" --session-owned --agent-ready --force

The tracker binding (`docs/conventions/work-items.yaml`) uses the default role labels. The repository is a personal one with no native Issue Types, and its live label set is `session-owned`, `needs-triage`, `agent-ready`, `category:general` and `type: task`.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does and why, including any labels it would pass to `create-item`.
