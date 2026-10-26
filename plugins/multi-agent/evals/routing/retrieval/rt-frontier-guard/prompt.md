---
description: "Where X happens: the file and function that swap a role's fan-out model for fanout.model, and the model used when fanout.model is unset"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "file: plugins/multi-agent/scripts/resolve-roles.sh; function: role_json; fallback: opus."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

When the fan-out guard is on, a role's fan-out variant can get `fanout.model` in place of the role's own model. Which file and function make that replacement, and which model does the code use when no configuration layer sets `fanout.model`? Reply in three lines:

file: <path from the current directory>
function: <function name>
fallback: <model>
