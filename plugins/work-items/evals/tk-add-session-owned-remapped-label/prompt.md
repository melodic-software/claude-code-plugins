---
description: 'add --session-owned resolves the session-owned role label from the binding (here remapped to local-session) the way the human-gated role resolves, applies it instead of the default, and leaves off the needs-triage floor and agent-ready. remapped-session-owned-label reads the reply. Read-only tools, graded on the reply.'
tags: [track, add, role-label, session-owned, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The item is created through the seam with the label local-session, no session-owned label, no needs-triage floor and no agent-ready label.'
---

/work-items:track add "Rename the export flag to --format" --session-owned --force

I am filing this because this session is about to do the work itself.

The tracker binding (`docs/conventions/work-items.yaml`) sets `tracker.config.role_labels["session-owned"]` to `local-session`. The repository is a personal one with no native Issue Types, and its live label set is `local-session`, `needs-triage`, `agent-ready`, `category:general` and `type: task`.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does and why, including the labels it passes to `create-item`.
